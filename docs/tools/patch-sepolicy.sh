# usage: patch-sepolicy.sh <domain...>   (e.g. kernel, or "*")  -> /root/work/vendor.patched.vhdx
set -e
cd /root/work
cp vendor.orig.raw vendor.raw
debugfs -R "dump /etc/selinux/precompiled_sepolicy /root/work/sepolicy.orig" vendor.raw 2>/dev/null
./sepermissive sepolicy.orig sepolicy.new "$@"
echo "byte diffs: $(cmp -l sepolicy.orig sepolicy.new 2>/dev/null | wc -l)  (sizes $(stat -c %s sepolicy.orig) -> $(stat -c %s sepolicy.new))"
P=/etc/selinux/precompiled_sepolicy
debugfs -R "ea_get -f /root/work/sepolicy.sel $P security.selinux" vendor.raw >/dev/null 2>&1
{ echo "rm $P"; echo "write /root/work/sepolicy.new $P"; echo "sif $P uid 0"; echo "sif $P gid 0"; echo "sif $P mode 0100644"; echo "ea_set -f /root/work/sepolicy.sel $P security.selinux"; } > cmds.txt
debugfs -w -f cmds.txt vendor.raw >/dev/null 2>&1
echo "label: $(debugfs -R "ea_get $P security.selinux" vendor.raw 2>/dev/null | tr -d '\n')"
debugfs -R "dump $P /root/work/sepolicy.check" vendor.raw 2>/dev/null; cmp sepolicy.new sepolicy.check && echo "image content verified"
e2fsck -fn vendor.raw 2>&1 | tail -1
rm -f vendor.patched.vhdx; qemu-img convert -f raw -O vhdx -o subformat=dynamic vendor.raw vendor.patched.vhdx; ls -l vendor.patched.vhdx
