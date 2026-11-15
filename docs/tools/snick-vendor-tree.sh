cd /root/work; rm -rf tv to; mkdir tv to
debugfs -R "rdump / tv" snick.vendor.raw >/dev/null 2>&1
debugfs -R "rdump / to" vendor.orig.raw >/dev/null 2>&1
echo "== files only in snickler vendor"; (cd tv; find . -type f | sort) > tv.list; (cd to; find . -type f | sort) > to.list
comm -23 tv.list to.list | head -60
echo "== files only in ours"; comm -13 tv.list to.list | head -60
echo "== files in both that differ"; comm -12 tv.list to.list | while read f; do cmp -s "tv/$f" "to/$f" || echo "$f  ($(stat -c %s "to/$f") -> $(stat -c %s "tv/$f"))"; done | head -60
