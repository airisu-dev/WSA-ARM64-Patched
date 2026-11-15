# Build patched system.vhdx + vendor.vhdx from the pristine raws in /root/work:
#  - 64-bit only: ro.zygote=zygote64, abilist=arm64-v8a, ALL ro.*.product.cpu.abilist32 lines DELETED
#    (system, vendor and the odm build.prop inside the vendor image)
#  - SELinux: domains given as args are made permissive in vendor precompiled_sepolicy (default: kernel)
# usage: patch-all.sh [domain...]   ("none" = leave the SELinux policy untouched = clean config; default: kernel)
set -e
cd /root/work
DOMS="${*:-kernel}"
for p in system vendor; do [ -f $p.orig.raw ] || cp $p.raw $p.orig.raw; cp $p.orig.raw $p.raw; done

replace_file() { # img path newfile : replace content, keep selinux label/owner/mode
  img=$1; path=$2; new=$3; b=$(basename $path)
  debugfs -R "ea_get -f /root/work/$b.sel $path security.selinux" $img >/dev/null 2>&1 || true
  { echo "rm $path"; echo "write $new $path"; echo "sif $path uid 0"; echo "sif $path gid 0"; echo "sif $path mode 0100644"
    [ -s $b.sel ] && echo "ea_set -f /root/work/$b.sel $path security.selinux"; } > cmds.txt
  debugfs -w -f cmds.txt $img >/dev/null 2>&1
  echo "  $img:$path label=$(debugfs -R "ea_get $path security.selinux" $img 2>/dev/null | tr -d '\n' | sed 's/.*= //')"
  rm -f $b.sel
}
patch_prop() { # img path
  img=$1; path=$2; b=$(echo $path | tr / _)
  debugfs -R "dump $path /root/work/$b.old" $img 2>/dev/null
  sed -E 's/^ro\.zygote=zygote64_32/ro.zygote=zygote64/; s/^debug\.stagefright\.ccodec=0/debug.stagefright.ccodec=4/; s/^(ro\.[a-z_]+\.product\.cpu\.abilist)=.*/\1=arm64-v8a/; /^ro\.[a-z_]+\.product\.cpu\.abilist32=/d' $b.old > $b.new
  if [ "$path" = /system/build.prop ]; then
    # init loads this file in the init domain, which may set these (the vendor build.prop silently ignored ro.com.google.gmsversion).
    # dex2oat64: installd otherwise runs the arm32 dex2oat32, which fails with "Exec format error" on this CPU, so no app is AOT-compiled.
    grep -vE '^(dalvik\.vm\.dex2oat64\.enabled|ro\.com\.google\.gmsversion)=' $b.new > $b.new2
    printf 'dalvik.vm.dex2oat64.enabled=true\nro.com.google.gmsversion=13_202304\n' >> $b.new2
    mv $b.new2 $b.new
  fi
  echo "--- $img:$path"; diff $b.old $b.new || true
  replace_file $img $path /root/work/$b.new
}
patch_prop vendor.raw /build.prop
patch_prop vendor.raw /odm/etc/build.prop
patch_prop system.raw /system/build.prop

if [ "$DOMS" = none ]; then
  echo "sepolicy: left UNCHANGED (clean config)"
else
  P=/etc/selinux/precompiled_sepolicy
  debugfs -R "dump $P /root/work/sepolicy.orig" vendor.raw 2>/dev/null
  ./sepermissive sepolicy.orig sepolicy.new $DOMS
  replace_file vendor.raw $P /root/work/sepolicy.new
fi

for p in system vendor; do e2fsck -fn $p.raw 2>&1 | tail -1; rm -f $p.patched.vhdx; qemu-img convert -f raw -O vhdx -o subformat=dynamic $p.raw $p.patched.vhdx; done
ls -l *.patched.vhdx
