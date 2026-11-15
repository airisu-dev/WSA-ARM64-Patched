cd /root/work
ls_names() { debugfs -R "ls -p $2" $1 2>/dev/null | awk -F/ 'NF>5 && $6!="." && $6!=".." && $3 ~ /^100/ {print $6}' | sort -u; }  # regular files only
ls_names system.orig.raw /system/lib   > o.lib32
ls_names system.orig.raw /system/lib64 > o.lib64
ls_names snick.system.raw /system/lib64 > s.lib64
ls_names snick.system.raw /system/lib   > s.lib32
echo "ours: lib32=$(wc -l < o.lib32) lib64=$(wc -l < o.lib64) | snickler: lib32=$(wc -l < s.lib32) lib64=$(wc -l < s.lib64)"
comm -23 o.lib32 o.lib64 > o.only32          # 32-bit-only libs in our image
comm -12 o.only32 s.lib64 > importable        # ...that snickler ships as 64-bit
comm -23 o.only32 s.lib64 > still_missing
echo "32-bit-only in ours: $(wc -l < o.only32)   importable from snickler lib64: $(wc -l < importable)   no 64-bit source: $(wc -l < still_missing)"
echo "== importable (first 60)"; head -60 importable
echo "== still missing (first 30)"; head -30 still_missing
echo "== snickler lib64 files not in ours (any)"; comm -13 o.lib64 s.lib64 | wc -l
