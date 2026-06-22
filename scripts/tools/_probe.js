const path = require('path'), os = require('os'), fs = require('fs');
const WAL = path.join(os.homedir(), '.zcode', 'cli', 'db', 'db.sqlite-wal');
const buf = fs.readFileSync(WAL);
const ps = buf.readInt32BE(8);
const pages = new Map();
let off = 32;
while (off + 24 + ps <= buf.length) { const n = buf.readUInt32BE(off); off += 24; if (n >= 1 && n <= 100000) pages.set(n, buf.slice(off, off + ps)); off += ps; }
function rv(b, o) { let r = 0; for (let i = 0; i < 9; i++) { const x = b[o + i]; if (i === 8) return [r, o + 9]; r = (r << 7) | (x & 0x7f); if (!(x & 0x80)) return [r, o + i + 1]; } return [r, o + 9]; }
function pc(b, o) { const [, o1] = rv(b, o); const [, o2] = rv(b, o1); const [hl, ds] = rv(b, o2); const he = o2 + hl; const ts = []; let p = ds; while (p < he) { const [t, np] = rv(b, p); ts.push(t); p = np; } const v = []; let d = he; for (const t of ts) { if (t === 0) v.push(null); else if (t === 1) { v.push(b.readInt8(d)); d += 1; } else if (t === 2) { v.push(b.readInt32BE(d)); d += 4; } else if (t === 5) { v.push(b.readDoubleBE(d)); d += 8; } else if (t === 6) { v.push(b.readUInt32BE(d + 4)); d += 8; } else if (t >= 12 && t % 2 === 0) { const n = (t - 12) / 2; v.push(b.slice(d, d + n).toString('utf8')); d += n; } else if (t >= 13 && t % 2 === 1) { const n = (t - 13) / 2; v.push(b.slice(d, d + n).toString('utf8')); d += n; } else v.push('T' + t); } return v; }
const all = [];
for (const pb of pages.values()) { if (pb[0] !== 0x0d) continue; const nc = pb.readInt16BE(3); for (let c = 0; c < nc; c++) { const co = pb.readInt16BE(8 + c * 2); try { all.push(pc(pb, co)); } catch (e) { } } }
const msg = all.filter(r => r[0] && String(r[0]).startsWith('msg_'));
msg.forEach((r, i) => {
  const s = String(r[4] || '');
  const roleM = s.match(/"role":"(user|assistant|tool|system)"/);
  const textM = s.match(/"text":"((?:[^"\\]|\\.)*)"/);
  console.log('msg' + i + ' role=' + (roleM ? roleM[1] : '?'));
  if (textM) console.log('  text: ' + textM[1].substring(0, 250).replace(/\\n/g, ' '));
});
