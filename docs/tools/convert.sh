set -e
mkdir -p /root/work && cd /root/work
S=/mnt/c/<path-to-installed-package>
for p in system vendor; do [ -f $p.raw ] || qemu-img convert -f vhdx -O raw $S/$p.vhdx $p.raw; done
ls -l
for p in system vendor; do echo "== $p"; debugfs -R "ls /" $p.raw 2>/dev/null | head -5; done
echo "== system build.prop"; debugfs -R "cat /system/build.prop" system.raw 2>/dev/null | grep -nE "zygote|abilist|cpu.abi"
echo "== vendor build.prop"; debugfs -R "cat /build.prop" vendor.raw 2>/dev/null | grep -nE "zygote|abilist|cpu.abi"
