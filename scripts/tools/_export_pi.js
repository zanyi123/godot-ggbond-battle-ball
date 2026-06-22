// 导出 pi 会话为可读 markdown
const fs = require('fs'), os = require('os'), path = require('path');
const f = process.argv[2];
const outFile = process.argv[3];
if (!f) { console.error('用法: node _export_pi.js <session.jsonl> [out.md]'); process.exit(1); }
const lines = fs.readFileSync(f, 'utf8').split('\n').filter(Boolean);
let out = '';
const first = JSON.parse(lines[0]);
out += `# pi 会话导出\n- 文件: ${path.basename(f)}\n- cwd: ${first.cwd}\n- 开始: ${new Date(first.timestamp).toISOString()}\n- 总行: ${lines.length}\n\n---\n\n`;

function textOf(content) {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return JSON.stringify(content);
  return content.map(c => {
    if (c.type === 'text') return c.text;
    if (c.type === 'thinking') return '';  // 思考不导出,太长
    if (c.type === 'tool_use') {
      const inp = c.input || {};
      const desc = inp.path || inp.command || inp.file_path || JSON.stringify(inp).slice(0, 150);
      return `> 🔧 工具[${c.name}] ${String(desc).slice(0, 200)}`;
    }
    if (c.type === 'tool_result') {
      const r = typeof c.content === 'string' ? c.content : JSON.stringify(c.content);
      return `> ↳ 结果: ${r.slice(0, 150).replace(/\n/g, ' ')}`;
    }
    return '';
  }).filter(Boolean).join('\n\n');
}

let userCount = 0, asstCount = 0;
for (const l of lines) {
  let j; try { j = JSON.parse(l); } catch (e) { continue; }
  if (j.type !== 'message') continue;
  const msg = j.message;
  if (!msg) continue;
  const role = msg.role;
  const text = textOf(msg.content);
  if (!text) continue;
  if (role === 'user') { userCount++; out += `### 🧑 用户\n\n${text}\n\n---\n\n`; }
  else if (role === 'assistant') { asstCount++; out += `### 🤖 pi\n\n${text}\n\n---\n\n`; }
}
out = out.replace(/^# pi 会话导出/, `# pi 会话导出\n- 用户消息: ${userCount} / 助手消息: ${asstCount}`);
if (outFile) { fs.mkdirSync(path.dirname(outFile), { recursive: true }); fs.writeFileSync(outFile, out, 'utf8'); console.log(`✅ 导出: ${outFile} (${userCount}用户/${asstCount}助手, ${out.length}字节)`); }
else process.stdout.write(out);
