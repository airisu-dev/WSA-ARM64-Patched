cd /root/work
cls() { printf 'class=%s mach=%s size=%s' "$(od -An -tx1 -j4 -N1 $1 | tr -d ' ')" "$(od -An -tx1 -j18 -N2 $1 | tr -d ' ')" "$(stat -c %s $1)"; }
for b in bin/hw/android.hardware.audio.service bin/hw/android.hardware.cas@1.2-service bin/hw/android.hardware.media.c2@1.0-service-goldfish bin/hw/android.hardware.media.omx@1.0-service bin/boringssl_self_test32 bin/boringssl_self_test64; do
  echo "== $b"
  for img in snick.vendor.raw vendor.orig.raw; do
    if debugfs -R "dump /$b /root/work/snick/x" $img >/dev/null 2>&1 && [ -s snick/x ]; then printf '   %-16s ' $img; cls snick/x; echo; cp snick/x snick/x.$img; else printf '   %-16s (absent)\n' $img; fi; rm -f snick/x
  done
  [ -f snick/x.snick.vendor.raw ] && [ -f snick/x.vendor.orig.raw ] && { cmp -s snick/x.snick.vendor.raw snick/x.vendor.orig.raw && echo "   -> identical" || echo "   -> DIFFERENT"; }
  rm -f snick/x.*
done
echo; echo "== audio launcher: needed libs (snickler)"
debugfs -R "dump /bin/hw/android.hardware.audio.service /root/work/snick/a" snick.vendor.raw >/dev/null 2>&1
grep -a -o -E 'lib[a-z0-9_.@+-]+\.so|android\.hardware\.[a-z.@0-9]+\.so' snick/a | sort -u | head -30
echo; echo "== lib/ (32-bit libs dir) present?"; debugfs -R "ls /lib" snick.vendor.raw 2>&1 | head -3; debugfs -R "ls /lib" vendor.orig.raw 2>&1 | head -3
