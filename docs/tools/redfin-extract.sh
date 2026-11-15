# HISTORICAL investigation script from an earlier session; the path below pointed at that session's scratchpad. Not part of the build.
# Extract system/vendor from the official Pixel 5 (redfin) TQ3A.230901.001 factory image into raw ext4.
set -e
dpkg -s android-sdk-libsparse-utils >/dev/null 2>&1 || { apt-get update -qq; DEBIAN_FRONTEND=noninteractive apt-get install -y -qq android-sdk-libsparse-utils unzip >/dev/null; }
which unzip >/dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt-get install -y -qq unzip >/dev/null
S=/mnt/c/<scratch-dir>/redfin
mkdir -p /root/redfin && cd /root/redfin
unzip -o -q $S/redfin-factory.zip '*/image-redfin-*.zip' -d outer
unzip -o -q outer/*/image-redfin-*.zip 'system.img' 'vendor.img' 'system_ext.img' 'product.img' -d inner 2>&1 | head -3 || true
ls -l inner
for p in system vendor; do [ -f $p.raw ] || simg2img inner/$p.img $p.raw; done
ls -l *.raw
for p in system vendor; do echo "== $p"; debugfs -R "ls /" $p.raw 2>/dev/null | tr -s ' ' | head -4; done
