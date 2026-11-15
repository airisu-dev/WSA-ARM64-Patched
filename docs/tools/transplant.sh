# Option 1: copy snickler's 64-bit launchers/libs into OUR patched vendor/system images (run after patch-all.sh).
# Sources (read-only): /root/work/snick.vendor.raw, /root/work/snick.system.raw   (from snickler/WSA-Patched 0.0.2)
set -e
cd /root/work
SV=snick.vendor.raw; SS=snick.system.raw; V=vendor.raw; S=system.raw

# vendor fs is ~99.7% full: grow it first
truncate -s 256M $V && e2fsck -fy $V >/dev/null 2>&1 || true
resize2fs $V >/dev/null 2>&1 && echo "vendor fs grown: $(debugfs -R stats $V 2>/dev/null | grep -E '^Block count' )"

# put_file <srcimg> <path> <dstimg> <mode> [keep_dst_label]
put_file() {
  src=$1; path=$2; dst=$3; mode=$4; keep=$5; b=$(echo $path | tr / _)
  debugfs -R "dump $path /root/work/tp.$b" $src >/dev/null 2>&1 || { echo "MISSING in source: $path"; return 1; }
  if [ "$keep" = keep ]; then lab=$dst; else lab=$src; fi
  debugfs -R "ea_get -f /root/work/tp.$b.sel $path security.selinux" $lab >/dev/null 2>&1 || true
  { debugfs -R "stat $path" $dst >/dev/null 2>&1 && echo "rm $path"
    echo "write /root/work/tp.$b $path"; echo "sif $path uid 0"; echo "sif $path gid 0"; echo "sif $path mode $mode"
    [ -s tp.$b.sel ] && echo "ea_set -f /root/work/tp.$b.sel $path security.selinux"; } > cmds.txt
  debugfs -w -f cmds.txt $dst >/dev/null 2>&1
  echo "  $dst:$path  $(debugfs -R "ea_get $path security.selinux" $dst 2>/dev/null | tr -d '\n' | sed 's/.*= //')"
  rm -f tp.$b tp.$b.sel
}

echo "== vendor: launchers, c2 HAL, manifest"
put_file $SV /bin/hw/android.hardware.audio.service           $V 0100755
put_file $SV /bin/hw/android.hardware.cas@1.2-service         $V 0100755
put_file $SV /bin/hw/android.hardware.media.c2@1.0-service-goldfish $V 0100755
put_file $SV /etc/init/android.hardware.media.c2@1.0-service-goldfish.rc $V 0100644
debugfs -R "stat /etc/seccomp_policy" $V >/dev/null 2>&1 || { echo "mkdir /etc/seccomp_policy" > cmds.txt; debugfs -w -f cmds.txt $V >/dev/null 2>&1; }
put_file $SV /etc/seccomp_policy/android.hardware.media.c2@1.2-default-seccomp_policy $V 0100644
put_file $SV /etc/vintf/manifest.xml                          $V 0100644 keep
printf 'rm /bin/hw/android.hardware.media.omx@1.0-service\nrm /etc/init/android.hardware.media.omx@1.0-service.rc\n' > cmds.txt
debugfs -w -f cmds.txt $V >/dev/null 2>&1 && echo "  removed OMX binary + rc"

echo "== vendor: 64-bit libs"
for f in lib64/android.hardware.cas@1.0.so lib64/android.hardware.cas@1.1.so lib64/android.hardware.cas@1.2.so lib64/android.hardware.cas.native@1.0.so \
  lib64/android.hardware.media.c2@1.0.so lib64/android.hardware.media.c2@1.1.so lib64/android.hardware.media.c2@1.2.so lib64/hw/android.hardware.cas.native@1.0.so \
  lib64/libavservices_minijail.so lib64/libcodec2_goldfish_avcdec.so lib64/libcodec2_goldfish_common.so lib64/libcodec2_goldfish_hevcdec.so \
  lib64/libcodec2_goldfish_vp8dec.so lib64/libcodec2_goldfish_vp9dec.so lib64/libcodec2_hidl@1.0.so lib64/libcodec2_hidl@1.1.so lib64/libcodec2_hidl@1.2.so \
  lib64/libcodec2_hidl_plugin.so lib64/libcodec2_vndk.so lib64/libgoldfish_codec2_store.so lib64/libstagefright_bufferpool@2.0.1.so; do
  put_file $SV /$f $V 0100644
done

echo "== system: 64-bit drmserver + mediaserver (keep OUR labels)"
put_file $SS /system/bin/drmserver    $S 0100755 keep
put_file $SS /system/bin/mediaserver  $S 0100755 keep

echo "== system: 64-bit libs that only existed as 32-bit (found via logcat: libmediaplayerservice not found)"
for f in libmediaplayerservice.so libresourcemanagerservice.so libstagefright_httplive.so; do
  put_file $SS /system/lib64/$f $S 0100644
done

for p in vendor system; do e2fsck -fn $p.raw 2>&1 | tail -1; rm -f $p.patched.vhdx; qemu-img convert -f raw -O vhdx -o subformat=dynamic $p.raw $p.patched.vhdx; done
ls -l *.patched.vhdx
