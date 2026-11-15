// usage: node mkcpio.js <out> <name>=<file> ...   builds a newc cpio of regular files (mode 0755)
const fs = require('fs');
const [out, ...ents] = process.argv.slice(2);
const bufs = [];
let ino = 1;
const pad4 = n => (4 - (n % 4)) % 4;
function add(name, data, mode) {
  const nm = Buffer.from(name + '\0');
  const f = v => v.toString(16).padStart(8, '0');
  const hdr = '070701' + f(ino++) + f(mode) + f(0) + f(0) + f(1) + f(0) + f(data.length) +
    f(0) + f(0) + f(0) + f(0) + f(nm.length) + f(0);
  bufs.push(Buffer.from(hdr), nm, Buffer.alloc(pad4(110 + nm.length)), data, Buffer.alloc(pad4(data.length)));
}
for (const e of ents) { const [n, p] = e.split('='); add(n, fs.readFileSync(p), 0o100755); }
add('TRAILER!!!', Buffer.alloc(0), 0);
fs.writeFileSync(out, Buffer.concat(bufs));
