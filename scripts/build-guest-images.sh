#!/bin/bash
# Build the four patched Android images (system, vendor, product, system_ext) from Microsoft's originals.
# Runs inside WSL2 Debian (aarch64). Called by build.ps1; can also be run by hand.
#
# usage: build-guest-images.sh <PAYLOAD_DIR> <DONOR_DIR> <GOOGLE_ZIP> <GAPPS_DIR> <EXTRA_DIR> <OUT_DIR>      (Windows paths as /mnt/c/...)
#   PAYLOAD_DIR  extracted WSA arm64 msix: system.vhdx vendor.vhdx product.vhdx system_ext.vhdx (Microsoft originals)
#   DONOR_DIR    the repo's donor/ folder: MANIFEST.tsv (which 64-bit files to take: mode, SELinux label, SHA-256, source) + vintf-manifest.xml
#   GOOGLE_ZIP   Google's Android 13 arm64 emulator image (arm64-v8a-33_r02.zip); the 64-bit files are extracted from it
#   GAPPS_DIR    extracted MindTheGapps zip (contains system/product/... and system/system_ext/...)
#   EXTRA_DIR    the repo's extra\ folder: component-overrides.xml (disables the Play Store's second package verifier)
#   OUT_DIR      receives system.vhdx vendor.vhdx product.vhdx system_ext.vhdx
#
# What it changes (see README.md, "What the build changes"):
#   1  props: 64-bit only (zygote64, ABI lists, no abilist32), ccodec=4, dex2oat64, gmsversion
#   2  vendor/system: 64-bit audio/CAS/Codec2 HALs, drmserver, mediaserver and their libs (from Google's image); OMX HAL removed
#   3  product/system_ext: Play Store, Play Services, Services Framework (no Magisk)
# The SELinux policy is NOT modified. Every written file keeps/gets an explicit SELinux label.
set -euo pipefail

[ $# -eq 6 ] || { sed -n '2,18p' "$0"; exit 2; }
PAYLOAD=$1; DONOR=$2; GZIP=$3; GAPPS=$4; EXTRA=$5; OUT=$6
HERE=$(cd "$(dirname "$0")" && pwd)
W=/root/wsa-build                       # scratch on WSL's own ext4 (raw images are several GB; /mnt/c is far too slow)

for f in "$PAYLOAD"/{system,vendor,product,system_ext}.vhdx "$DONOR/MANIFEST.tsv" "$DONOR/vintf-manifest.xml" "$GZIP" "$HERE/lp_extract.py" "$EXTRA/component-overrides.xml" \
         "$GAPPS/system/product/priv-app/GmsCore/GmsCore.apk" "$GAPPS/system/product/priv-app/Phonesky/Phonesky.apk" \
         "$GAPPS/system/system_ext/priv-app/GoogleServicesFramework/GoogleServicesFramework.apk"; do
  [ -f "$f" ] || { echo "MISSING INPUT: $f" >&2; exit 1; }
done
need=""
command -v qemu-img  >/dev/null || need="$need qemu-utils"
command -v debugfs   >/dev/null || need="$need e2fsprogs"
command -v resize2fs >/dev/null || need="$need e2fsprogs"
command -v unzip     >/dev/null || need="$need unzip"
command -v python3   >/dev/null || need="$need python3"
if [ -n "$need" ]; then echo "installing:$need"; apt-get update -qq; DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $need; fi

rm -rf "$W"; mkdir -p "$W" "$OUT"; cd "$W"

# ---- helpers (debugfs exits 0 even when it fails, so every check parses its output) --------------------------------
dfs()    { debugfs -w -R "$2" "$1" >/dev/null 2>&1; }                                  # dfs <img> "<cmd>"
exists() { ! debugfs -R "stat $2" "$1" 2>&1 | grep -q 'File not found'; }               # exists <img> <path>
label()  { debugfs -R "ea_get -f $3 $2 security.selinux" "$1" >/dev/null 2>&1; [ -s "$3" ]; }   # label <img> <path> <outfile>
grow()   { truncate -s "$2" "$1"; e2fsck -fy "$1" >/dev/null 2>&1 || true; resize2fs "$1" >/dev/null 2>&1; }

mkdirs() {   # mkdirs <img> <dir> <labelfile>  (creates missing parents, labelled)
  local img=$1 cur="" part
  for part in $(echo "$2" | tr '/' ' '); do
    cur="$cur/$part"
    exists "$img" "$cur" || { dfs "$img" "mkdir $cur"; dfs "$img" "sif $cur uid 0"; dfs "$img" "sif $cur gid 0"
                              dfs "$img" "sif $cur mode 040755"; dfs "$img" "ea_set -f $3 $cur security.selinux"; }
  done
}
install_file() {   # install_file <dstimg> <srcfile> <dstpath> <mode> <labelfile>   (replaces an existing file, sets owner/mode/label)
  local img=$1 src=$2 dst=$3 mode=$4 lab=$5
  [ -f "$src" ] || { echo "MISSING SOURCE: $src" >&2; exit 1; }
  mkdirs "$img" "$(dirname "$dst")" "$lab"
  exists "$img" "$dst" && dfs "$img" "rm $dst"
  dfs "$img" "write $src $dst"; dfs "$img" "sif $dst uid 0"; dfs "$img" "sif $dst gid 0"
  dfs "$img" "sif $dst mode $mode"; dfs "$img" "ea_set -f $lab $dst security.selinux"
  exists "$img" "$dst" || { echo "WRITE FAILED: $dst in $img" >&2; exit 1; }
  [ "$(debugfs -R "ea_get $dst security.selinux" "$img" 2>/dev/null | tr -d '\0\n' | sed 's/.*= //')" ] || { echo "NO LABEL on $dst" >&2; exit 1; }
}
prepare_donor() {   # unpack Google's emulator image once: $W/g/vendor.raw and $W/g/system.raw (ext4 filesystems the 64-bit files are read from)
  mkdir -p "$W/g"
  unzip -q -j -o "$GZIP" "*/vendor.img" "*/system.img" -d "$W/g"
  python3 "$HERE/lp_extract.py" "$W/g/vendor.img" "$W/g/system.img" "$W/g"
  rm -f "$W/g/vendor.img" "$W/g/system.img"
  for g in vendor system; do debugfs -R "stat /" "$W/g/$g.raw" >/dev/null 2>&1 || { echo "Google $g image is not ext4" >&2; exit 1; }; done
}
install_donor() {   # install every file listed in $DONOR/MANIFEST.tsv: image, path, mode, selinux_label, sha256, bytes, label_source, kind, source
  # source: google = same path in Google's image, google:<path> = another path there, repo:<file> = a file in $DONOR
  local img path mode lab sha bytes lsrc kind source f n=0 gp
  prepare_donor
  while IFS=$'\t' read -r img path mode lab sha bytes lsrc kind source; do
    case "$img" in '#'*|'') continue;; esac
    f="$W/donor.bin"; rm -f "$f"
    case "$source" in
      repo:*)   cp "$DONOR/${source#repo:}" "$f" ;;
      google)   debugfs -R "dump $path $f" "$W/g/$img.raw" >/dev/null 2>&1 || true ;;
      google:*) gp=${source#google:}; debugfs -R "dump $gp $f" "$W/g/$img.raw" >/dev/null 2>&1 || true ;;
      *) echo "bad source '$source' for $path" >&2; exit 1 ;;
    esac
    [ -s "$f" ] || { echo "MISSING donor file ($source): $img$path" >&2; exit 1; }
    [ "$(sha256sum "$f" | cut -d' ' -f1)" = "$sha" ] || { echo "SHA-256 mismatch: $img$path ($source)" >&2; exit 1; }
    if [ "$lsrc" = keep ]; then label "$img.raw" "$path" "$W/lab.donor" || { echo "no label for $path" >&2; exit 1; }   # destination's own label
    else printf '%s\0' "$lab" > "$W/lab.donor"; fi                                                                      # recorded label (with the trailing NUL xattrs carry)
    install_file "$img.raw" "$f" "$path" "0100${mode#0}" "$W/lab.donor"; n=$((n+1))
  done < "$DONOR/MANIFEST.tsv"
  rm -rf "$W/g" "$W/donor.bin"
  echo "  installed $n donor files (extracted from Google's image, SHA-256 checked, labels applied)"
}
patch_props() {   # patch_props <img> <path> [extra lines to append]
  local img=$1 path=$2 extra=${3:-} f="$W/prop.$$"
  debugfs -R "dump $path $f.old" "$img" >/dev/null 2>&1; [ -s "$f.old" ] || { echo "cannot read $path" >&2; exit 1; }
  # 64-bit zygote; ABI lists = arm64 only; DELETE abilist32 (an empty value still matches the init trigger "=*"); codecs back on
  sed -E 's/^ro\.zygote=zygote64_32/ro.zygote=zygote64/; s/^debug\.stagefright\.ccodec=0/debug.stagefright.ccodec=4/;
         s/^(ro\.[a-z_]+\.product\.cpu\.abilist)=.*/\1=arm64-v8a/; /^ro\.[a-z_]+\.product\.cpu\.abilist32=/d' "$f.old" > "$f.new"
  [ -n "$extra" ] && printf '%s\n' "$extra" >> "$f.new"
  label "$img" "$path" "$f.lab" || { echo "no label for $path" >&2; exit 1; }
  install_file "$img" "$f.new" "$path" 0100644 "$f.lab"
  echo "  $img:$path  ($(diff "$f.old" "$f.new" | grep -c '^[<>]') changed lines)"; rm -f "$f".*
}

# ---- 1/5 raw images ------------------------------------------------------------------------------------------------
echo "== 1/5 convert VHDX -> raw ext4"
for n in system vendor product system_ext; do qemu-img convert -f vhdx -O raw "$PAYLOAD/$n.vhdx" $n.raw
  debugfs -R "stat /" $n.raw >/dev/null 2>&1 || { echo "$n.vhdx is not ext4" >&2; exit 1; }; done

# ---- 2/5 properties ------------------------------------------------------------------------------------------------
echo "== 2/5 properties"
patch_props vendor.raw /build.prop
patch_props vendor.raw /odm/etc/build.prop
# system build.prop is loaded by init in the init domain, which may set these; the vendor file ignores ro.com.google.gmsversion.
# dex2oat64: otherwise installd runs the arm32 dex2oat32, which fails with "Exec format error" (no app gets AOT-compiled)
patch_props system.raw /system/build.prop $'dalvik.vm.dex2oat64.enabled=true\nro.com.google.gmsversion=13_202304'

# ---- 3/5 64-bit services (vendor + system) ------------------------------------------------------------------------
echo "== 3/5 64-bit audio/CAS/Codec2 HALs, drmserver, mediaserver"
grow vendor.raw 256M                    # the original vendor filesystem is ~99.7% full
install_donor        # vendor: audio/CAS/Codec2 HALs, rc, seccomp policy, VINTF manifest (swaps the OMX entry for Codec2), 21 libs
                     # system: drmserver, mediaserver, and the 3 libs that only existed as 32-bit in /system/lib
dfs vendor.raw "rm /bin/hw/android.hardware.media.omx@1.0-service"; dfs vendor.raw "rm /etc/init/android.hardware.media.omx@1.0-service.rc"
exists vendor.raw /bin/hw/android.hardware.media.omx@1.0-service && { echo "OMX HAL still present" >&2; exit 1; }

# ---- 4/5 Google apps -----------------------------------------------------------------------------------------------
echo "== 4/5 Google apps (Play Store, Play Services, Services Framework)"
grow product.raw 512M; grow system_ext.raw 256M
label product.raw /priv-app lab.product; label system_ext.raw /priv-app lab.system_ext
G=$GAPPS/system
for f in priv-app/GmsCore/GmsCore.apk priv-app/Phonesky/Phonesky.apk etc/permissions/privapp-permissions-google-product.xml \
         etc/sysconfig/d2d_cable_migration_feature.xml etc/sysconfig/google.xml etc/sysconfig/google_build.xml \
         etc/sysconfig/google-hiddenapi-package-allowlist.xml etc/default-permissions/default-permissions-google.xml \
         etc/default-permissions/default-permissions-mtg.xml; do
  install_file product.raw "$G/product/$f" "/$f" 0100644 lab.product; done
# REQUIRED, not shipped by MindTheGapps: WSA already has a package verifier (Microsoft's com.microsoft.windows.userapp) and Android requires
# EXACTLY ONE. The Play Store declares a second one, so without this file system_server dies in PackageManagerService ("There must be
# exactly one verifier"), restarts every ~5 s, and WSA kills the guest after ~126 s ("Starting Windows Subsystem for Android" forever).
# It disables the Play Store's PackageVerificationReceiver (and the stock OTA components). See extra\component-overrides.xml.
install_file product.raw "$EXTRA/component-overrides.xml" /etc/sysconfig/component-overrides.xml 0100644 lab.product
for f in priv-app/GoogleServicesFramework/GoogleServicesFramework.apk etc/permissions/privapp-permissions-google-system-ext.xml; do
  install_file system_ext.raw "$G/system_ext/$f" "/$f" 0100644 lab.system_ext; done
# Not installed on purpose: Velvet (245 MB), speech services, TalkBack, overlays (GoogleWebViewOverlay would point the WebView
# provider at a Google WebView that is not installed), dialer-support jar, SetupWizard.

# ---- 5/5 check + convert back ---------------------------------------------------------------------------------------
echo "== 5/5 fsck and convert to VHDX"
for n in system vendor product system_ext; do
  r=$(e2fsck -fn $n.raw 2>&1 | tail -1); echo "  $n: $r"
  case "$r" in *"clean"*|*files*blocks*) ;; *) echo "fsck problem in $n" >&2; exit 1;; esac
  qemu-img convert -f raw -O vhdx -o subformat=dynamic $n.raw "$OUT/$n.vhdx"
done
echo; ls -l "$OUT"/{system,vendor,product,system_ext}.vhdx
echo "DONE"
