# Build sepermissive (marks SELinux domains permissive in a binary policy; only needed for the DEBUG build, patch-all.sh kernel).
# Run in Debian (WSL2, aarch64). Needs gcc + libsepol-dev (installed automatically). Output: /root/work/sepermissive
# NOTE: it must link the STATIC libsepol.a: the internal policydb_* symbols are not exported by the shared library.
set -e
command -v gcc >/dev/null || { apt-get update -qq; DEBIAN_FRONTEND=noninteractive apt-get install -y -qq gcc libc6-dev >/dev/null; }
dpkg -s libsepol-dev >/dev/null 2>&1 || { apt-get update -qq; DEBIAN_FRONTEND=noninteractive apt-get install -y -qq libsepol-dev >/dev/null; }
T=$(dirname "$(readlink -f "$0")")
mkdir -p /root/work
gcc -O2 -o /root/work/sepermissive "$T/sepermissive.c" /usr/lib/aarch64-linux-gnu/libsepol.a
ls -l /root/work/sepermissive
dpkg -l libsepol-dev | tail -1
