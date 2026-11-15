# Read the guest kernel log written by the kmsg logger to the tail of the live metadata.2/userdata.2 disk. Works while the VM runs.
# usage (in Debian): bash readlog.sh [metadata|userdata]      -> /root/work/<disk>.log.txt
# The live disks are in %LOCALAPPDATA%\Packages\MicrosoftCorporationII.WindowsSubsystemForAndroid_8wekyb3d8bbwe\LocalCache
set -e
cd /root/work
LA=$(wslpath "$(cmd.exe /c 'echo %LOCALAPPDATA%' 2>/dev/null | tr -d '\r')")
L="$LA/Packages/MicrosoftCorporationII.WindowsSubsystemForAndroid_8wekyb3d8bbwe/LocalCache"
d=${1:-metadata}
rm -f $d.2.copy.vhdx $d.2.raw
cp "$L/$d.2.vhdx" $d.2.copy.vhdx
qemu-img check -r all $d.2.copy.vhdx >/dev/null 2>&1 || true   # replay the VHDX log (needed if the VM is running)
qemu-img convert -f vhdx -O raw $d.2.copy.vhdx $d.2.raw
# the log is the first NUL-terminated chunk of the last 1 MiB (older, longer runs may leave stale text after it)
tail -c 1048576 $d.2.raw | awk 'BEGIN{RS="\0"} NR==1{printf "%s", $0; exit}' > $d.log.txt
wc -c $d.log.txt
