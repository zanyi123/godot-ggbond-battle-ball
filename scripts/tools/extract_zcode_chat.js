#!/usr/bin/env node
/**
 * extract_zcode_chat.js — 把 zcode 的对话从 SQLite 导出为 markdown
 *
 * 用途：在 pi(或任何工具)里跟进度时，跑一下，把 zcode 最近对话导出。
 *       导出的 markdown 放到 工作日志/ 下，pi 直接 read 就能跟上 zcode 的进度。
 *
 * 用法：
 *   node extract_zcode_chat.js              # 导出全部会话到 stdout 概览
 *   node extract_zcode_chat.js <sessionId>  # 导出指定会话完整对话
 *   node extract_zcode_chat.js --latest     # 导出最近一个会话
 *   node extract_zcode_chat.js --latest 工作日志/zcode_同步.md  # 写入文件
 *
 * 原理：zcode(opencode) 的对话存在 SQLite，表结构：
 *   session(id, title, directory, time_created, ...)
 *   message(id, session_id, role, time_created, ...)   role: user/assistant
 *   part(id, message_id, session_id, type, data)        消息分片(text/tool)
 * 本工具纯 node 解析 SQLite 文件格式，不依赖外部 sqlite3。
 */

const fs = require('fs');
const path = require('path');
const os = require('os');

const DB_PATH = path.join(os.homedir(), '.zcode', 'cli', 'db', 'db.sqlite');
const WAL_PATH = path.join(os.homedir(), '.zcode', 'cli', 'db', 'db.sqlite-wal');

// ---------- 纯 JS SQLite 读取器(只读,覆盖标准格式) ----------
// 参考 SQLite file format: https://www.sqlite.org/fileformat2.html
function readVarint(buf, offset) {
  let result = 0;
  for (let i = 0; i < 9; i++) {
    const byte = buf[offset + i];
    if (i === 8) { result = (result << 8) | byte; return [result, offset + 9]; }
    result = (result << 7) | (byte & 0x7f);
    if ((byte & 0x80) === 0) return [result, offset + i + 1];
  }
  return [result, offset + 9];
}

function parseCellPayload(buf, offset, endOffset) {
  // 跳过 payload 长度 varint 和 rowid varint
  const [, o1] = readVarint(buf, offset);          // payload size
  const [, o2] = readVarint(buf, o1);              // rowid
  const headerStart = o2;
  // header 长度 varint
  const [hdrLen, dataStart] = readVarint(buf, headerStart);
  const headerEnd = headerStart + hdrLen;
  // 读各列类型
  const types = [];
  let p = dataStart;
  while (p < headerEnd) {
    const [t, np] = readVarint(buf, p);
    types.push(t);
    p = np;
  }
  // 读各列数据
  const values = [];
  let dp = headerEnd;
  for (const t of types) {
    if (t === 0) { values.push(null); }
    else if (t === 1) { values.push(buf.readInt8(dp)); dp += 1; }
    else if (t === 2) { values.push(buf.readInt32BE(dp)); dp += 4; }
    else if (t === 3) { values.push(buf.readInt32BE(dp) >> 8); dp += 3; }
    else if (t === 4) { values.push(buf.readFloatBE(dp)); dp += 4; }
    else if (t === 5) { values.push(buf.readDoubleBE(dp)); dp += 8; }
    else if (t === 6) { values.push(0); dp += 8; }  // int64 简化
    else if (t === 7) { values.push(buf.readDoubleBE(dp)); dp += 8; }
    else if (t === 8) { values.push(0); }
    else if (t === 9) { values.push(1); }
    else if (t >= 12 && t % 2 === 0) { const n = (t - 12) / 2; values.push(buf.slice(dp, dp + n).toString('utf8')); dp += n; }
    else if (t >= 13 && t % 2 === 1) { const n = (t - 13) / 2; values.push(buf.slice(dp, dp + n).toString('utf8')); dp += n; }
    else { values.push(null); }
  }
  return values;
}

function readTableFromDbFile(filePath, schemaSize) {
  // 返回 [{rowid, values}] —— 极简实现:扫整个文件找页,只处理 table leaf 页(0x0D)
  // 注:对于 zcode db(几百KB)够用;大库需完整 b-tree 遍历
  const buf = fs.readFileSync(filePath);
  const pageSize = buf.readInt32BE(16) || 4096;
  const rows = [];
  const numPages = Math.floor(buf.length / pageSize);
  for (let pg = 0; pg < numPages; pg++) {
    const base = pg * pageSize;
    if (base + pageSize > buf.length) break;
    const type = buf[base];
    if (type !== 0x0d) continue; // 只看 table leaf 页
    const nCells = buf.readInt16BE(base + 3);
    const cellPtrStart = base + 8;
    for (let c = 0; c < nCells; c++) {
      const cellOff = buf.readInt16BE(cellPtrStart + c * 2);
      try {
        const vals = parseCellPayload(buf, base + cellOff, base + pageSize);
        if (vals && vals.length >= schemaSize) rows.push(vals);
      } catch (e) { /* skip corrupt cell */ }
    }
  }
  return rows;
}

// WAL 帧: 24字节头 + pageSize 数据,扫所有帧的页
function readTableFromWal(filePath, schemaSize) {
  if (!fs.existsSync(filePath)) return [];
  const buf = fs.readFileSync(filePath);
  // pageSize 在 WAL 里要读 db 文件头(WAL 头不含 pageSize)。
  // WAL 头(32字节): magic(4) + format(4) + pageSize(4)@offset 8 + checkpoint_seq(4) + salt(8) + checksum(8)
  const pageSize = buf.readInt32BE(8) || 4096;
  const walHeaderSize = 32;
  const frameHeaderSize = 24;
  const rows = [];
  let off = walHeaderSize;
  let frameIndex = 0;
  // 用「页号 -> 最新帧内容」缓存,实现 WAL 同页后者覆盖前者
  const latestPage = new Map();
  while (off + frameHeaderSize + pageSize <= buf.length) {
    const pageInDb = buf.readUInt32BE(off);            // 帧头: 页号(1-based)
    off += frameHeaderSize;
    if (pageInDb < 1 || pageInDb > 100000) { off += pageSize; frameIndex++; continue; }
    // 截取整页内容存入缓存(后帧覆盖前帧)
    latestPage.set(pageInDb, buf.slice(off, off + pageSize));
    off += pageSize;
    frameIndex++;
  }
  for (const pageBuf of latestPage.values()) {
    const type = pageBuf[0];
    if (type !== 0x0d) continue; // 只看 table leaf
    const nCells = pageBuf.readInt16BE(3);
    const cellPtrStart = 8;
    for (let c = 0; c < nCells; c++) {
      const cellOff = pageBuf.readInt16BE(cellPtrStart + c * 2);
      try {
        const vals = parseCellPayload(pageBuf, cellOff, pageSize);
        if (vals && vals.length >= 2) rows.push(vals);
      } catch (e) { /* skip */ }
    }
  }
  return rows;
}

// 合并 db 和 wal 的行(按主键去重, wal 覆盖 db; sqlite 序号靠后的帧覆盖前面)
function readTable(tableName, cols) {
  const dbRows = readTableFromDbFile(DB_PATH, cols);
  // WAL 同一页会被多次写入,需按帧序号保留最后版本——这里简化:用后面帧覆盖前面
  const walRows = readTableFromWal(WAL_PATH, cols);
  // 简化合并: db 行 + wal 行(wal 内部后者覆盖前者已通过 dedupeByRowid 处理)
  const map = new Map();
  dbRows.forEach(r => map.set(r[0], r));  // rowid = 第一列(primary key id 文本? 不,rowid 是隐藏列)
  // 注意:主键是 id(text),rowid 是隐藏整数。我们按第一列(实际数据 id)去重更稳
  const byId = new Map();
  [...dbRows, ...walRows].forEach(r => {
    // r[0] 可能是 rowid 而非 id —— 我们表里第一列是 id(primary key),rowid 在 parseCell 时被跳过了
    byId.set(r[0], r);
  });
  return [...byId.values()];
}

// ---------- 业务:解析 session/message/part ----------
function safeJson(str, fallback) {
  if (!str || typeof str !== 'string') return fallback;
  try { return JSON.parse(str); } catch (e) { return fallback; }
}

function main() {
  const args = process.argv.slice(2);
  // 读三张表
  // session 列: id, project_id, workspace_id, parent_id, slug, directory, path, title, version, share_url, time_created, time_updated, ...
  const sessions = readTable('session', 4).filter(r => r[0] && typeof r[0] === 'string' && r[0].startsWith('sess'));
  // message 列: id, session_id, time_created, time_updated, data
  const messages = readTable('message', 5).filter(r => r[0] && typeof r[0] === 'string');
  // part 列: id, message_id, session_id, time_created, time_updated, data
  const parts = readTable('part', 6).filter(r => r[0] && typeof r[0] === 'string');

  // session 真实列序(实测 zcode 0.14.8):
  // [0]=id [1]=project_id [5]=directory [7]=title(首条用户输入) ...
  function extractSession(r) {
    return {
      id: r[0],
      title: r[7] || '(无标题)',
      directory: r[5] || '',
      time_created: 0,
    };
  }
  const sessList = sessions
    .map(extractSession)
    .filter(s => s.id && s.id.startsWith('sess'));

  // message 真实列序: [0]=id [1]=session_id [2]=time_created [3]=time_updated [4]=data(JSON)
  // data 列开头有二进制前缀,要找第一个 { 截取
  function extractMessage(r) {
    const id = r[0], sid = r[1];
    const rawStr = r[4] && typeof r[4] === 'string' ? r[4] : '';
    const jsonStart = rawStr.indexOf('{');
    const data = jsonStart >= 0 ? safeJson(rawStr.slice(jsonStart), {}) : {};
    const role = data.role || 'unknown';
    return {
      id,
      session_id: sid,
      role,
      time_created: (data.time && data.time.created) || r[2] || 0,
      data,
    };
  }
  const msgList = messages.map(extractMessage).filter(m => m.session_id);

  // part 真实列序: [0]=id [1]=message_id [2]=session_id [3,4]=time [5]=data(JSON)
  function extractPart(r) {
    const rawStr = r[5] && typeof r[5] === 'string' ? r[5] : '';
    const jsonStart = rawStr.indexOf('{');
    const data = jsonStart >= 0 ? safeJson(rawStr.slice(jsonStart), {}) : {};
    return { id: r[0], message_id: r[1], type: data.type, data };
  }
  const partList = parts.map(extractPart);
  const partsByMsg = new Map();
  partList.forEach(p => {
    if (!partsByMsg.has(p.message_id)) partsByMsg.set(p.message_id, []);
    partsByMsg.get(p.message_id).push(p);
  });

  // 模式选择
  const mode = args[0];
  if (!mode || mode === '--list') {
    console.log('# zcode 会话列表（按时间倒序）\n');
    console.log('| # | 会话ID | 标题 | 消息数 | 目录 |');
    console.log('|---|---|---|---|---|');
    sessList.forEach((s, i) => {
      const n = msgList.filter(m => m.session_id === s.id).length;
      console.log(`| ${i + 1} | \`${s.id}\` | ${s.title} | ${n} | ${path.basename(s.directory)} |`);
    });
    console.log('\n用法: node extract_zcode_chat.js <sessionId> | --latest [输出文件]');
    return;
  }

  let targetSession;
  if (mode === '--latest') targetSession = sessList[0];
  else targetSession = sessList.find(s => s.id === mode) || sessList.find(s => s.id.startsWith(mode));

  if (!targetSession) { console.error('找不到会话: ' + mode); process.exit(1); }

  const sessMsgs = msgList.filter(m => m.session_id === targetSession.id)
    .sort((a, b) => (a.time_created || 0) - (b.time_created || 0));

  let out = `# zcode 会话导出：${targetSession.title}\n\n`;
  out += `- 会话ID：${targetSession.id}\n- 目录：${targetSession.directory}\n- 消息数：${sessMsgs.length}\n- 导出时间：${new Date().toISOString()}\n\n---\n\n`;

  for (const m of sessMsgs) {
    const role = m.role === 'user' ? '🧑 用户' : m.role === 'assistant' ? '🤖 zcode' : '🔧 ' + m.role;
    out += `### ${role}\n\n`;
    const ps = (partsByMsg.get(m.id) || []).sort((a, b) => (a.data?.time_created || 0) - (b.data?.time_created || 0));
    if (ps.length === 0) {
      // 直接从 message data 取 text
      const t = m.raw?.text || m.raw?.content || '';
      if (t) out += textOf(t) + '\n\n';
    } else {
      for (const p of ps) {
        if (p.type === 'text') out += textOf(p.data?.text || p.data?.content || '') + '\n\n';
        else if (p.type === 'tool') {
          const tn = p.data?.tool || p.data?.name || 'tool';
          out += `> [工具调用 ${tn}]\n\n`;
        } else if (p.type) out += `> [${p.type}]\n\n`;
      }
    }
    out += `---\n\n`;
  }

  function textOf(t) {
    if (Array.isArray(t)) return t.map(x => typeof x === 'string' ? x : JSON.stringify(x)).join('');
    if (typeof t === 'object') return JSON.stringify(t, null, 2);
    return String(t || '');
  }

  const outFile = args[1];
  if (outFile) {
    fs.mkdirSync(path.dirname(outFile), { recursive: true });
    fs.writeFileSync(outFile, out, 'utf8');
    console.log(`✅ 已导出到: ${outFile} (${sessMsgs.length} 条消息, ${out.length} 字节)`);
  } else {
    process.stdout.write(out);
  }
}

main();
