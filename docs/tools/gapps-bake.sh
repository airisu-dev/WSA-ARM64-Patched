# Bake a MINIMAL Google set (Play Store, Play Services, Services Framework) into product + system_ext (no Magisk).
# Source: /root/work/gapps_x  (extracted from the original package's lsp_gapps.img, MindTheGapps 13 arm64)
# Run AFTER patch-all.sh and transplant.sh (it also adds ro.com.google.gmsversion to vendor.raw).
set -e
cd /root/work
S=/root/work/gapps_x

for n in product system_ext; do cp $n.orig.raw $n.raw; done
grow() { img=$1; size=$2; truncate -s $size $img; e2fsck -fy $img >/dev/null 2>&1 || true; resize2fs $img >/dev/null 2>&1; echo "  $img grown: $(debugfs -R stats $img 2>/dev/null | grep -E '^Block count')"; }
grow product.raw 512M
grow system_ext.raw 256M

# label template per image, taken from an existing directory in that image
for n in product system_ext; do debugfs -R "ea_get -f /root/work/lab.$n /priv-app security.selinux" $n.raw >/dev/null 2>&1; echo "  $n label: $(tr -d '\0' < lab.$n)"; done

dw() { debugfs -w -R "$2" $1 >/dev/null 2>&1; }
mkdirs() { # img dir  (creates missing parents, labelled)
  img=$1; n=${img%.raw}; cur=""
  for part in $(echo "$2" | tr '/' ' '); do
    cur="$cur/$part"
    if debugfs -R "stat $cur" $img 2>&1 | grep -q "File not found"; then
      dw $img "mkdir $cur"; dw $img "sif $cur uid 0"; dw $img "sif $cur gid 0"; dw $img "sif $cur mode 040755"; dw $img "ea_set -f /root/work/lab.$n $cur security.selinux"
    fi
  done
}
put() { # img srcfile dstpath
  img=$1; src=$2; dst=$3; n=${img%.raw}
  [ -f "$src" ] || { echo "MISSING SOURCE: $src"; return 1; }
  mkdirs $img "$(dirname $dst)"
  debugfs -R "stat $dst" $img >/dev/null 2>&1 && ! debugfs -R "stat $dst" $img 2>&1 | grep -q "File not found" && dw $img "rm $dst"
  dw $img "write $src $dst"; dw $img "sif $dst uid 0"; dw $img "sif $dst gid 0"; dw $img "sif $dst mode 0100644"; dw $img "ea_set -f /root/work/lab.$n $dst security.selinux"
  printf '  %-12s %-72s %s\n' "$n" "$dst" "$(debugfs -R "ea_get $dst security.selinux" $img 2>/dev/null | tr -d '\0\n' | sed 's/.*= //')"
}

echo "== product"
put product.raw $S/product/priv-app/GmsCore/GmsCore.apk           /priv-app/GmsCore/GmsCore.apk
put product.raw $S/product/priv-app/Phonesky/Phonesky.apk         /priv-app/Phonesky/Phonesky.apk
put product.raw $S/product/etc/permissions/privapp-permissions-google-product.xml /etc/permissions/privapp-permissions-google-product.xml
for f in component-overrides d2d_cable_migration_feature google google_build google-hiddenapi-package-allowlist; do put product.raw $S/product/etc/sysconfig/$f.xml /etc/sysconfig/$f.xml; done
for f in default-permissions-google default-permissions-mtg; do put product.raw $S/product/etc/default-permissions/$f.xml /etc/default-permissions/$f.xml; done
echo "== system_ext"
put system_ext.raw $S/system_ext/priv-app/GoogleServicesFramework/GoogleServicesFramework.apk /priv-app/GoogleServicesFramework/GoogleServicesFramework.apk
put system_ext.raw $S/system_ext/etc/permissions/privapp-permissions-google-system-ext.xml     /etc/permissions/privapp-permissions-google-system-ext.xml


for n in product system_ext vendor; do echo "fsck $n: $(e2fsck -fn $n.raw 2>&1 | tail -1)"; rm -f $n.patched.vhdx; qemu-img convert -f raw -O vhdx -o subformat=dynamic $n.raw $n.patched.vhdx; done
ls -l product.patched.vhdx system_ext.patched.vhdx vendor.patched.vhdx system.patched.vhdx | awk '{print $5, $9}'
