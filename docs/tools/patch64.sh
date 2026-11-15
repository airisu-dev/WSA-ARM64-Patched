set -e
cd /root/work
# fresh raw copies each run so the patch is idempotent
for p in system vendor; do [ -f $p.orig.raw ] || cp $p.raw $p.orig.raw; cp $p.orig.raw $p.raw; done

patch_file() {  # image path sedscript
  img=$1; path=$2; script=$3; base=$(basename $path)
  debugfs -R "dump $path /root/work/$base.old" $img 2>/dev/null
  debugfs -R "ea_get -f /root/work/$base.sel $path security.selinux" $img >/dev/null 2>&1 || true
  sed -E "$script" $base.old > $base.new
  echo "--- diff $img:$path"; diff $base.old $base.new || true
  { echo "rm $path"; echo "write /root/work/$base.new $path"; echo "sif $path uid 0"; echo "sif $path gid 0"; echo "sif $path mode 0100644"
    [ -s $base.sel ] && echo "ea_set -f /root/work/$base.sel $path security.selinux"; } > cmds.txt
  debugfs -w -f cmds.txt $img >/dev/null 2>&1
  echo "selinux label now: $(debugfs -R "ea_get $path security.selinux" $img 2>/dev/null | tr -d '\n')"
  rm -f $base.sel
}
patch_file vendor.raw /build.prop 's/^ro\.zygote=zygote64_32/ro.zygote=zygote64/; s/^(ro\.vendor\.product\.cpu\.abilist)=.*/\1=arm64-v8a/; s/^(ro\.vendor\.product\.cpu\.abilist32)=.*/\1=/'
patch_file system.raw /system/build.prop 's/^(ro\.system\.product\.cpu\.abilist)=.*/\1=arm64-v8a/; s/^(ro\.system\.product\.cpu\.abilist32)=.*/\1=/'
e2fsck -fn vendor.raw | tail -2; e2fsck -fn system.raw | tail -2
for p in system vendor; do rm -f $p.patched.vhdx; qemu-img convert -f raw -O vhdx -o subformat=dynamic $p.raw $p.patched.vhdx; done
ls -l *.vhdx
