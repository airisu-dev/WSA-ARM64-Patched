# Research scripts (not part of the build)

These are the scripts and sample logs used while diagnosing the boot failure. **Nothing here is needed to build or install
WSA**: `..\..\build.ps1` and `..\..\scripts\build-guest-images.sh` are the supported recipe. Keep these for debugging or as a
record of how a finding was obtained. Run them inside WSL Debian (aarch64) as root. Scripts marked *paths* have scratch
locations from the original session hard-coded and must be edited first.

## Still useful for debugging a new failure

| File | Purpose |
|---|---|
| `kmsglog.c`, `build-logger.sh` *(paths)*, `mkcpio.js`, `readlog.sh` *(paths)* | Early-boot kernel-log capture for a guest that dies before logd; see "Seeing the guest log" in `..\tooling-notes.md` |
| `sepermissive.c`, `build-sepermissive.sh`, `patch-sepolicy.sh` | Make the `kernel` SELinux domain permissive so the logger survives enforcement (debug only) |
| `patch-all.sh [kernel\|none]` | The first, manual version of the property patching (`kernel` adds the permissive policy, `none` does not) |
| `libgap.sh`, `libgap-vendor.sh` | List libraries that exist only as 32-bit (in `lib/`, not `lib64/`) |
| `elf` / `codec` helpers: `redfin-elf.sh`, `snick-elf.sh`, `codecs.sh`, `codecs2.sh`, `codec-use.sh`, `avcinfo.sh`, `playstate.sh`, `browsers.sh`, `collect-media-info.sh` | One-off inspection of ELF class, decoder lists, playback state and device comparisons |

## Superseded by the build (historical)

| File | Superseded by |
|---|---|
| `transplant.sh`, `patch64.sh`, `convert.sh`, `gapps-bake.sh` | `scripts\build-guest-images.sh` |
| `snick-*.sh`, `redfin-extract.sh` *(paths)* | The tracked `donor\` folder and `donor\MANIFEST.tsv` |

## Samples

| File | What it shows |
|---|---|
| `sample-guest-kmsg-selinux-stage.txt` | Guest log up to the SELinux policy load (where the logger stops) |
| `sample-guest-kmsg-second-stage-boringssl32-failure.txt` | The root-cause failure: `boringssl_self_test32` → `Exec format error` → shutdown |
| `sample-guest-kmsg-boot-completed.txt` | A healthy boot reaching `sys.boot_completed=1` |
| `sample-collect-arm64-snapdragon-x.txt` | Media/codec environment of this device |
