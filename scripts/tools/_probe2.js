const path = require('path'), os = require('os'), fs = require('fs');
const WAL = path.join(os.homedir(), '.zcode', 'cli', 'db', 'db.sqlite-wal');
const buf = fs.readFileSync(WAL);
const ps = buf.readInt32BE(8);
const pages = new Map();
let off = 32;
while (off + 24 + ps <= buf.length) { const n = buf.readUInt32BE(off); off += 24; if (n >= 1 && n <= 100000) pages.set(n, buf.slice(off, off + ps)); off += ps; }
function rv(b, o) { let r = 0; for (let i = 0; i < 9; i++) { const x = b[o + i]; if (i === 8) return [r, o + 9]; r = (r << 7) | (x & 0x7f); if (!(x & 0x80)) return [r, o + i + 1]; } return [r, o + 9]; }
// 完整解析:含溢出页
function pc(b, o, pageBuf, allPages) {
  let [, o1] = rv(b, o);          // payload size
  const [, o2] = rv(b, o1);       // rowid
  // payload 可能溢出: 若 payload > 页内可用,走溢出链
  const usable = ps;              // 简化
  // 先读 header
  const [hl] = rv(b, o2);
  // 判断是否溢出(粗略): 若 header+payload 超出页尾
  // 这里先不处理溢出,直接按页内解析
  const he = o2 + hl;
  const ts = []; let p = o2 + hl - hl; // header start
  // 重读 header
  p = o2 + (rv(b, o2)[0]); // 错,简化
  return null;
}
// 改用最简单:直接看 msg 行第4列的原始字节长度
const all = [];
for (const pb of pages.values()) { if (pb[0] !== 0x0d) continue; const nc = pb.readInt16BE(3); for (let c = 0; c < nc; c++) { const co = pb.readInt16BE(8 + c * 2); 
  try {
    const b = pb;
    const [, o1] = rv(b, co);
    const [payloadSize, o2] = rv(b, o1);
    const [rowid, hdrStart] = rv(b, o2);
    const [hdrLen] = rv(b, hdrStart);
    const dataColStart = hdrStart + hdrLen;
    // 看 payload 是否溢出(超过页剩余空间)
    const pageAvail = ps - co - (hdrStart - co); // 粗略
    all.push({ id: '?', payloadSize, pageAvail, overflow: payloadSize > (ps - co) });
  } catch(e){}
}}
console.log('msg行 payload 大小分布:');
all.slice(0,10).forEach((x,i)=>console.log(i, 'payload='+x.payloadSize, 'overflow='+x.overflow));
