cd /root/work
mkdir -p snick && cd snick && rm -rf v && mkdir v
# dump rc + build.prop and ELF headers from snickler vendor, ours from vendor.orig.raw
debugfs -R "rdump /etc/init v" snick.vendor.raw >/dev/null 2>&1 || true
cd /root/work
rm -rf snick/v snick/o; mkdir -p snick/v snick/o
debugfs -R "rdump /etc/init snick/v" snick.vendor.raw 2>/dev/null
debugfs -R "rdump /etc/init snick/o" vendor.orig.raw 2>/dev/null
debugfs -R "dump /build.prop snick/v.build.prop" snick.vendor.raw 2>/dev/null
debugfs -R "dump /build.prop snick/o.build.prop" vendor.orig.raw 2>/dev/null
echo "== init rc files only in snickler / only in ours"
diff <(ls snick/v/init | sort) <(ls snick/o/init | sort) | head -30
echo "== rc content diffs (shared files)"
for f in $(ls snick/v/init); do [ -f snick/o/init/$f ] && ! cmp -s snick/v/init/$f snick/o/init/$f && { echo "##### $f"; diff snick/o/init/$f snick/v/init/$f | head -40; }; done
echo "== build.prop diff (ours -> snickler)"; diff snick/o.build.prop snick/v.build.prop | head -30
echo "== ELF class/machine of key binaries (snickler | ours)"
for b in bin/hw/android.hardware.audio.service bin/hw/android.hardware.cas@1.2-service bin/hw/android.hardware.media.c2@1.0-service-goldfish bin/boringssl_self_test32 bin/hw/android.hardware.media.omx@1.0-service; do
  for img in snick.vendor.raw vendor.orig.raw; do
    debugfs -R "dump /$b /root/work/snick/x" $img >/dev/null 2>&1 && printf '%-52s %-18s class=%s mach=%s\n' "$b" "$img" "$(xxd -s4 -l1 -p snick/x)" "$(xxd -s18 -l2 -p snick/x)" || printf '%-52s %-18s (absent)\n' "$b" "$img"
    rm -f snick/x
  done
done
