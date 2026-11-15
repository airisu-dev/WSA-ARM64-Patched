echo "=== resumed/top"; dumpsys activity activities | grep -E "topResumedActivity|ResumedActivity:" | head -3
echo; echo "=== newpipe processes"; ps -A | grep -i newpipe | head
echo; echo "=== resource manager (codec clients)"; dumpsys media.resource_manager 2>&1 | head -25
echo; echo "=== audio flinger tracks"; dumpsys media.audio_flinger 2>&1 | grep -E "Output thread|Standby: |tracks|Tracks|^ +[0-9]+ +[0-9a-f]+ +[0-9]+" | head -12
echo; echo "=== media sessions"; dumpsys media_session 2>&1 | grep -iE "newpipe|state=|PlaybackState" | head -6
