# Build the early-boot kmsg logger (static arm64 binary) next to this script. Run in Debian (WSL2, aarch64).
# Needs gcc + libc6-dev (installed automatically). Output: kmsglog (same folder). Debug tool only (see docs/tooling-notes.md); it is not part of the build.
set -e
which gcc >/dev/null 2>&1 || { apt-get update -qq; DEBIAN_FRONTEND=noninteractive apt-get install -y -qq gcc libc6-dev >/dev/null; }
T=$(dirname "$(readlink -f "$0")")
gcc -O2 -static -Wall -o "$T/kmsglog" "$T/kmsglog.c"
file "$T/kmsglog" 2>/dev/null || ls -l "$T/kmsglog"
