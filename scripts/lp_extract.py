#!/usr/bin/env python3
"""Extract the ext4 filesystems we need from Google's Android emulator system image (arm64-v8a-33_r02.zip).

usage: lp_extract.py <vendor.img> <system.img> <OUT_DIR>      ->  OUT_DIR/vendor.raw, OUT_DIR/system.raw

vendor.img  is a GPT disk; its first partition is the ext4 'vendor' filesystem.
system.img  is a GPT disk; its 2nd partition is a dynamic-partition 'super' image that holds 'system', 'system_ext', 'product', 'vendor'
            as linear extents. We parse the LP metadata (geometry at super+4096, metadata at super+12288) and copy out the 'system' extent.
Plain Python 3, no external tools (lpunpack is not needed).
"""
import struct, sys, os

CHUNK = 16 << 20

def gpt_partitions(f):
    f.seek(512); h = f.read(92)
    if h[:8] != b'EFI PART': raise SystemExit('not a GPT disk')
    ent_lba = struct.unpack('<Q', h[72:80])[0]; n, es = struct.unpack('<II', h[80:88])
    f.seek(ent_lba * 512); ents = f.read(n * es); parts = []
    for i in range(n):
        e = ents[i * es:(i + 1) * es]; first, last = struct.unpack('<QQ', e[32:48])
        if first: parts.append((first * 512, (last - first + 1) * 512))
    return parts

def copy_range(f, off, size, dst):
    f.seek(off)
    with open(dst, 'wb') as o:
        left = size
        while left:
            b = f.read(min(CHUNK, left)); assert b, 'short read'; o.write(b); left -= len(b)

def main(vendor_img, system_img, out):
    os.makedirs(out, exist_ok=True)
    with open(vendor_img, 'rb') as f:
        off, size = gpt_partitions(f)[0]; copy_range(f, off, size, os.path.join(out, 'vendor.raw'))
    with open(system_img, 'rb') as f:
        parts = gpt_partitions(f); base = parts[1][0]
        f.seek(base + 4096); assert struct.unpack('<I', f.read(4))[0] == 0x616C4467, 'bad LP geometry'
        f.seek(base + 12288); hd = f.read(256); assert struct.unpack('<I', hd[:4])[0] == 0x414C5030, 'bad LP metadata'
        hsize = struct.unpack('<I', hd[8:12])[0]
        po, pn, pe, eo, en, ee = struct.unpack('<IIIIII', hd[4+2+2+4+32+4+32:4+2+2+4+32+4+32+24])
        f.seek(base + 12288 + hsize); T = f.read(max(po + pn * pe, eo + en * ee) + 64)
        exts = [struct.unpack('<QIQI', T[eo + i * ee:eo + i * ee + 24]) for i in range(en)]
        for i in range(pn):
            p = T[po + i * pe:po + (i + 1) * pe]
            if p[:36].split(b'\0')[0] != b'system': continue
            first, num = struct.unpack('<II', p[40:48])
            if num != 1: raise SystemExit('system partition is not a single extent')
            sectors, ttype, sector, _ = exts[first]
            if ttype != 0: raise SystemExit('system extent is not linear')
            copy_range(f, base + sector * 512, sectors * 512, os.path.join(out, 'system.raw')); return
    raise SystemExit("no 'system' partition in the LP metadata")

if __name__ == '__main__':
    if len(sys.argv) != 4: raise SystemExit(__doc__)
    main(*sys.argv[1:])
