# Collect media/codec facts from an Android guest so two WSA setups can be compared (e.g. arm64 vs x64).
# Run ON the device:   adb shell sh /data/local/tmp/collect-media-info.sh
# Everything is read-only. Output is plain text.

echo "##### 1. identity"
for p in ro.build.fingerprint ro.product.model ro.product.manufacturer ro.product.device ro.product.cpu.abilist \
         ro.product.cpu.abilist32 ro.product.cpu.abilist64 ro.zygote ro.build.version.release ro.build.version.sdk; do
  echo "$p=$(getprop $p)"
done

echo; echo "##### 2. media / codec properties"
getprop | grep -iE "stagefright|ccodec|codec2|swcodec|media\.|omx|c2\."

echo; echo "##### 3. media services / processes"
ps -A | grep -iE "media|codec|omx|c2@|audioserver|drm" | grep -v grep
echo "--- lshal (media-related)"
lshal 2>/dev/null | grep -iE "media|omx|c2|codec|IComponentStore"

echo; echo "##### 4. decoder list (name | owner | software-only | hw-accelerated | vendor)"
dumpsys media.player > /data/local/tmp/mp_full.txt 2>&1
awk '
  /^Media type/ { mt=$0 }
  /Decoder "/   { kind="Decoder"; name=$2; next }
  /Encoder "/   { kind="Encoder"; name=$2; next }
  /software-only:/ { so=$2 }
  /hw-accelerated:/ { hw=$2 }
  /vendor:/ { vd=$2 }
  /owner:/ { print mt " | " kind " " name " | owner " $2 " | sw-only " so " | hw " hw " | vendor " vd }
' /data/local/tmp/mp_full.txt | sed 's/,//g' | head -80
echo "(full dump saved on device: /data/local/tmp/mp_full.txt)"

echo; echo "##### 5. H.264 decoder profile/levels"
awk "/Media type 'video\/avc'/{f=1} f&&/Encoder infos/{exit} f" /data/local/tmp/mp_full.txt | head -60

echo; echo "##### 6. YouTube-family app: format/capability report from the last playback attempt"
echo "(play a video first, then run this script)"
logcat -d 2>/dev/null | grep -E "YT.qoe|noneavailable|canH264|PLAYER_ERROR|PlaybackServiceException" | tail -12

echo; echo "##### 7. installed YouTube-family apps"
pm list packages -f | grep -iE "youtube|morphe|revanced|gms|newpipe|firefox"
