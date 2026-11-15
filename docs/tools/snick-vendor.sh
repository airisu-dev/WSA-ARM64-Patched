# HISTORICAL investigation script from an earlier session; the path below is a placeholder for a scratch directory. Not part of the build.
set -e
cd /root/work
S=/mnt/c/<scratch-dir>/snickler-0.0.2
[ -f snick.vendor.raw ] || qemu-img convert -f vhdx -O raw $S/vendor.vhdx snick.vendor.raw
echo "== ls /  (snickler vendor)"; debugfs -R "ls /" snick.vendor.raw 2>/dev/null | tr -s ' ' | head -8
echo; echo "== bin + bin/hw executables"; for d in /bin /bin/hw; do debugfs -R "ls -l $d" snick.vendor.raw 2>/dev/null | awk '{print $NF, $6}' | head -60; done | sed -n 1,90p
