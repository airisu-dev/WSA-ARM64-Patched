cd /root/work
ls_names() { debugfs -R "ls -p $2" $1 2>/dev/null | awk -F/ 'NF>5 && $6!="." && $6!=".." && $3 ~ /^100/ {print $6}' | sort -u; }
ls_names vendor.orig.raw /lib   > vo.lib32; ls_names vendor.orig.raw /lib64 > vo.lib64; ls_names snick.vendor.raw /lib64 > vs.lib64
comm -23 vo.lib32 vo.lib64 > vo.only32
echo "vendor 32-bit-only libs in ours: $(wc -l < vo.only32)"
echo "== importable from snickler vendor lib64"; comm -12 vo.only32 vs.lib64
echo "== no 64-bit source anywhere (also checking system lib64 of ours)"; comm -23 vo.only32 vs.lib64 | while read f; do grep -qx "$f" o.lib64 || echo "$f"; done | head -40
