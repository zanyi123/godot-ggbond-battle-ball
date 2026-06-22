// 只读诊断:直接扫主库 db.sqlite,看 session/message/part 行的真实列
const path = require('path'), os = require('os'), fs = require('fs');
const DB = path.join(os.homedir(), '.zcode', 'cli', 'db', 'db.sqlite');
const buf = fs.readFileSync(DB);
const ps = buf.readInt32BE(16) || 4096;
function rv(b, o) { let r = 0; for (let i = 0; i < 9; i++) { const x = b[o + i]; if (i === 8) return [r, o + 9]; r = (r << 7) | (x & 0x7f); if (!(x & 0x80)) return [r, o + i + 1]; } return [r, o + 9]; }
function pc(b, o) {
  const [, o1] = rv(b, o);       // payload size
  const [, o2] = rv(b, o1);      // rowid
  const [hl, ds] = rv(b, o2);    // header len
  const he = o2 + hl;
  const ts = []; let p = ds;
  while (p < he) { const [t, np] = rv(b, p); ts.push(t); p = np; }
  const v = []; let d = he;
  for (const t of ts) {
    if (t === 0) v.push(null);
    else if (t === 1) { v.push(b.readInt8(d)); d += 1; }
    else if (t === 2) { v.push(b.readInt32BE(d)); d += 4; }
    else if (t === 3) { v.push((b.readInt32BE(d) >> 8)); d += 3; }
    else if (t === 4) { v.push(b.readFloatBE(d)); d += 4; }
    else if (t === 5) { v.push(b.readDoubleBE(d)); d += 8; }
    else if (t === 6) { v.push('int64'); d += 8; }
    else if (t === 7) { v.push(b.readDoubleBE(d)); d += 8; }
    else if (t === 8) { v.push(0); }
    else if (t === 9) { v.push(1); }
    else if (t >= 12 && t % 2 === 0) { const n = (t - 12) / 2; v.push(b.slice(d, d + n).toString('utf8')); d += n; }
    else if (t >= 13 && t % 2 === 1) { const n = (t - 13) / 2; v.push(b.slice(d, d + n).toString('utf8')); d += n; }
    else v.push('T' + t);
  }
  return v;
}
const all = [];
for (let pg = 0; pg * ps < buf.length; pg++) {
  const base = pg * ps;
  if (buf[base] !== 0x0d) continue;
  const nc = buf.readInt16BE(base + 3);
  for (let c = 0; c < nc; c++) {
    const co = buf.readInt16BE(base + 8 + c * 2);
    try { const v = pc(buf, base + co); if (v) all.push(v); } catch (e) {}
  }
}
console.log('总行数:', all.length);
// 统计前缀
const prefixes = {};
for (const r of all) {
  if (typeof r[0] === 'string' && /_[a-zA-Z0-9]{8}/.test(r[0])) {
    const pf = r[0].split('_')[0];
    prefixes[pf] = (prefixes[pf] || 0) + 1;
  }
}
console.log('行前缀统计:', JSON.stringify(prefixes));

// 各类样本: 打印第一条 sess / msg / part 的所有列(截断长字符串)
function sample(prefix) {
  const r = all.find(x => typeof x[0] === 'string' && x[0].startsWith(prefix + '_'));
  if (!r) { console.log('\n[' + prefix + '] 无样本'); return; }
  console.log('\n[' + prefix + '] 样本, 列数=' + r.length);
  r.forEach((c, i) => {
    let s = typeof c === 'string' ? c : (c === null ? 'NULL' : String(c));
    if (s.length > 120) s = s.slice(0, 120) + '…(' + s.length + '字节)';
    console.log('  [' + i + ']: ' + s);
  });
}
sample('sess');
sample('msg');
sample('part');
