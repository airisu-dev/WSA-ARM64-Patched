echo "=== codecs advertised (dumpsys media.player)"
dumpsys media.player 2>&1 | grep -iE "Media Codec|Codec|decoder|encoder|OMX|c2\." | head -50
echo
echo "=== media props"
getprop | grep -iE "swcodec|media|codec2|stagefright" | head -20
echo
echo "=== processes"
ps -A | grep -iE "swcodec|mediacodec|media\.|c2@|codec" | head
echo
echo "=== services registered"
service list 2>&1 | grep -iE "media|codec" | head -20
echo
echo "=== hwservices (lshal)"
lshal 2>/dev/null | grep -iE "media|c2|omx|codec|ComponentStore" | head
