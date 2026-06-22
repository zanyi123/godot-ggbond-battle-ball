// 临时调试:dump zcode db 的真实列结构
const path = require('path'), os = require('os'), fs = require('fs');
const DB = path.join(os.homedir(), '.zcode', 'cli', 'db', 'db.sqlite');
const WAL = path.join(os.homedir(), '.zcode', 'cli', 'db', 'db.sqlite-wal');

function readVarint(buf, offset) {
  let result = 0;
  for (let i = 0; i < 9; i++) {
    const byte = buf[offset + i];
    if (i === 8) { return [result, offset + 9]; }
    result = (result << 7) | (byte & 0x7f);
    if ((byte & 0x80) === 0) return [result, offset + i + 1];
  }
  return [result, offset + 9];
}
function parseCellPayload(buf, offset) {
  const [, o1] = readVarint(buf, offset);
  const [, o2] = readVarint(buf, o1);
  const [hdrLen, dataStart] = readVarint(buf, o2);
  const headerEnd = o2 + hdrLen;
  const types = []; let p = dataStart;
  while (p < headerEnd) { const [t, np] = readVarint(buf, p); types.push(t); p = np; }
  const values = []; let dp = headerEnd;
  for (const t of types) {
    if (t === 0) values.push(null);
    else if (t === 1) { values.push(buf.readInt8(dp)); dp += 1; }
    else if (t === 2) { values.push(buf.readInt32BE(dp)); dp += 4; }
    else if (t === 3) { values.push(buf.readInt32BE(dp) >> 8); dp += 3; }
    else if (t === 6) { const lo = buf.readUInt32BE(dp+4); values.push(lo); dp += 8; }
    else if (t >= 12 && t % 2 === 0) { const n = (t - 12) / 2; values.push(buf.slice(dp, dp + n).toString('utf8')); dp += n; }
    else if (t >= 13 && t % 2 === 1) { const n = (t - 13) / 2; values.push(buf.slice(dp, dp + n).toString('utf8')); dp += n; }
    else { values.push('T' + t + '@' + dp); }
  }
  return values;
}
function scanPages(filePath) {
  const buf = fs.readFileSync(filePath);
  const pageSize = filePath.endsWith('-wal') ? buf.readInt32BE(8) : (buf.readInt32BE(16) || 4096);
  const rows = [];
  const pages = new Map();
  if (filePath.endsWith('-wal')) {
    let off = 32;
    while (off + 24 + pageSize <= buf.length) {
      const pgNo = buf.readUInt32BE(off); off += 24;
      if (pgNo >= 1 && pgNo <= 100000) pages.set(pgNo, buf.slice(off, off + pageSize));
      off += pageSize;
    }
  } else {
    const n = Math.floor(buf.length / pageSize);
    for (let pg = 1; pg <= n; pg++) pages.set(pg, buf.slice((pg-1)*pageSize, pg*pageSize));
  }
  for (const pageBuf of pages.values()) {
    if (pageBuf[0] !== 0x0d) continue;
    const nCells = pageBuf.readInt16BE(3);
    for (let c = 0; c < nCells; c++) {
      const co = pageBuf.readInt16BE(8 + c * 2);
      try { rows.push(parseCellPayload(pageBuf, co)); } catch (e) {}
    }
  }
  return rows;
}
console.log('===== DB 行数:', scanPages(DB).length, ' WAL 行数:', scanPages(WAL).length);
const all = [...scanPages(DB), ...scanPages(WAL)];
// 按"含 role 字段"和"含 title"分类
console.log('\n===== 含 "role" 的行(前2条) =====');
all.filter(r => r.some(c => typeof c === 'string' && c.includes('"role"'))).slice(0, 2).forEach((r, i) => {
  console.log('--- role 行 ' + i + ' (列数 ' + r.length + ') ---');
  r.forEach((c, j) => console.log('  [' + j + '] ' + JSON.stringify(c).substring(0, 150)));
});
console.log('\n===== 含 "title" 的行(前2条) =====');
all.filter(r => r.some(c => typeof c === 'string' && c.includes('"title"'))).slice(0, 2).forEach((r, i) => {
  console.log('--- title 行 ' + i + ' (列数 ' + r.length + ') ---');
  r.forEach((c, j) => console.log('  [' + j + '] ' + JSON.stringify(c).substring(0, 120)));
});
