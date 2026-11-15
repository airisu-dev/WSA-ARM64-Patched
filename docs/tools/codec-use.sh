echo "=== media.resource_manager (active codec clients)"; dumpsys media.resource_manager 2>&1 | head -30
echo; echo "=== audio flinger: active tracks"; dumpsys media.audio_flinger 2>&1 | grep -iE "Output thread|Standby|Active|tracks|Track|mixer|Failed|no audio" | head -12
echo; echo "=== firefox window/activity"; dumpsys activity activities 2>&1 | grep -E "mResumedActivity|ResumedActivity" | head -3
