# HISTORICAL investigation script from an earlier session; the path below pointed at that session's scratchpad. Not part of the build.
cd /root/work
S=/mnt/c/<scratch-dir>/snickler-0.0.2
[ -f snick.system.raw ] || qemu-img convert -f vhdx -O raw $S/system.vhdx snick.system.raw
cls() { printf 'class=%s mach=%s size=%s' "$(od -An -tx1 -j4 -N1 $1 | tr -d ' ')" "$(od -An -tx1 -j18 -N2 $1 | tr -d ' ')" "$(stat -c %s $1)"; }
for b in system/bin/drmserver system/bin/mediaserver system/bin/app_process32 system/bin/app_process64 system/bin/boringssl_self_test32; do
  for img in snick.system.raw system.orig.raw; do
    if debugfs -R "dump /$b /root/work/snick/x" $img >/dev/null 2>&1 && [ -s snick/x ]; then printf '%-34s %-18s ' "$b" $img; cls snick/x; echo; else printf '%-34s %-18s (absent)\n' "$b" $img; fi; rm -f snick/x
  done
done
echo "== system build.prop (snickler)"; debugfs -R "cat /system/build.prop" snick.system.raw 2>/dev/null | grep -E 'ro.zygote|abilist|cpu.abi|fingerprint|ro.build.(flavor|type)|ro.product.system.(name|model)' | head
echo "== system/lib (32-bit) present?"; debugfs -R "ls /system/lib" snick.system.raw 2>&1 | head -2
echo "== zygote rc imported"; debugfs -R "ls /system/etc/init/hw" snick.system.raw 2>/dev/null | tr -s ' ' | head -3
