echo "=== lines mentioning video/avc"; grep -n "video/avc" /data/local/tmp/mp.txt | head
echo; echo "=== context around avc decoder entry (before and after)"; n=$(grep -n 'Decoder "c2.android.avc.decoder"' /data/local/tmp/mp.txt | head -1 | cut -d: -f1); echo "line $n"; sed -n "$((n-8)),$((n+14))p" /data/local/tmp/mp.txt
echo; echo "=== media types present in decoder list"; grep -E "^  Media type|^ *Media type" /data/local/tmp/mp.txt | head -30
echo; echo "=== total lines: $(wc -l < /data/local/tmp/mp.txt)"
