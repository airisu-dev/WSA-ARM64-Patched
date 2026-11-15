cd /root/work
echo "=== vendor_file_contexts (ours -> snickler)"; diff to/etc/selinux/vendor_file_contexts tv/etc/selinux/vendor_file_contexts
echo; echo "=== vintf manifest (ours -> snickler)"; diff to/etc/vintf/manifest.xml tv/etc/vintf/manifest.xml
echo; echo "=== windows.permissions.xml"; diff to/etc/permissions/windows.permissions.xml tv/etc/permissions/windows.permissions.xml
echo; echo "=== c2 rc (snickler)"; cat tv/etc/init/android.hardware.media.c2@1.0-service-goldfish.rc
echo; echo "=== omx rc (ours)"; cat to/etc/init/android.hardware.media.omx@1.0-service.rc
