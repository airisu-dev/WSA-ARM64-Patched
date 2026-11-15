cd /root/redfin
for p in system vendor; do [ -e $p.raw ] || ln -s inner/$p.img $p.raw; done
cls() { printf 'class=%s mach=%s size=%s' "$(od -An -tx1 -j4 -N1 $1 | tr -d ' ')" "$(od -An -tx1 -j18 -N2 $1 | tr -d ' ')" "$(stat -c %s $1)"; }
chk() { # img path
  if debugfs -R "dump $2 /root/redfin/x" $1 >/dev/null 2>&1 && [ -s x ]; then printf '%-8s %-62s ' $1 $2; cls x; echo; else printf '%-8s %-62s (absent/not ext4)\n' $1 $2; fi; rm -f x; }
echo "== fs type"; debugfs -R "stats" system.raw 2>&1 | head -2; debugfs -R "ls /" system.raw 2>/dev/null | tr -s ' ' | head -3
echo "== candidates"
for f in /system/bin/drmserver /system/bin/mediaserver /system/bin/app_process32 /system/bin/app_process64 /system/bin/boringssl_self_test32; do chk system.raw $f; done
for f in /bin/hw/android.hardware.audio.service /bin/hw/android.hardware.audio@7.1-service /bin/hw/android.hardware.audio.service-aidl /bin/hw/android.hardware.cas@1.2-service /bin/hw/android.hardware.media.omx@1.0-service /bin/hw/android.hardware.media.c2@1.0-service-goldfish; do chk vendor.raw $f; done
echo "== all /vendor/bin/hw"; debugfs -R "ls /bin/hw" vendor.raw 2>/dev/null | tr -s ' ' | head -20
echo "== zygote/abi on redfin"; debugfs -R "cat /build.prop" vendor.raw 2>/dev/null | grep -E 'ro.zygote|abilist' ; debugfs -R "cat /system/build.prop" system.raw 2>/dev/null | grep -E 'ro.zygote|abilist'
