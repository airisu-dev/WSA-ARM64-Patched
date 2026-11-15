# donor: the 64-bit Android binaries this build needs

Microsoft's WSA ships a few Android services only as 32-bit ARM executables, and the Snapdragon X cannot run those. These
32 files are the 64-bit (AArch64) replacements, kept in the repository so the build does not need to download or unpack anything
for them. `build-guest-images.sh` installs exactly the files listed in `MANIFEST.tsv`.

## Origin

Extracted, unmodified, from the `vendor.vhdx` and `system.vhdx` inside the release asset
[snickler/WSA-Patched `0.0.2`](https://github.com/snickler/WSA-Patched/releases/tag/0.0.2) (`wsa-patched-0.0.2.7z`, 578,898,572 bytes,
SHA-256 `b1582feef760fdd7cd9897de767a37d5d476a91187f1fb7b50e86786e56e265a`; inside, `vendor.vhdx` is `d7604cb53721650592798f0a0b354b234ee502daebda999868de5f5132bb87ae`
and `system.vhdx` is `a252f372b17ce4eab4dccf79453011a0ca7a8ad96e8b59af2081b0a3b27533d1`).
Extraction: unpack the two images, convert them to raw ext4 (`qemu-img convert -f vhdx -O raw`), then `debugfs dump` each file and read its mode and
`security.selinux` label from the image. The files below are byte-identical to the donor's.

## What is here

| | Files | Notes |
|---|---|---|
| `vendor/bin/hw/` | `android.hardware.audio.service`, `android.hardware.cas@1.2-service`, `android.hardware.media.c2@1.0-service-goldfish` | the three 64-bit HAL launchers (audio, CAS, Codec2) that replace the arm32 ones |
| `vendor/etc/` | the Codec2 service `.rc`, its seccomp policy, `vintf/manifest.xml` | the manifest swaps the OMX entry for the Codec2 one |
| `vendor/lib64/` | 21 libraries (CAS, Codec2, goldfish software decoders, minijail, bufferpool) | 64-bit counterparts the new HALs link against |
| `system/system/bin/` | `drmserver`, `mediaserver` | 64-bit builds of the two arm32 media services |
| `system/system/lib64/` | `libmediaplayerservice.so`, `libresourcemanagerservice.so`, `libstagefright_httplive.so` | these existed only as 32-bit in `/system/lib`, so the 64-bit `mediaserver` could not link |

`MANIFEST.tsv` columns: image, path inside the image, mode, SELinux label, SHA-256, size, label source, kind.
`label_source = keep` means the build keeps the label of the file it replaces in Microsoft's image (`/vendor/etc/vintf/manifest.xml`, `drmserver`, `mediaserver`) instead of the recorded one.

## Integrity

- The build checks every file against its SHA-256 in `MANIFEST.tsv` before installing it, and stops on a mismatch.
- When this folder was created, every executable and library was checked to be a 64-bit ARM ELF (`class 2`, machine `0xB7`).

## Trust and licensing

These are unsigned binaries built by a third party (AOSP-derived, Apache-2.0 for the AOSP parts) and of unknown build provenance. They only ever run inside the
Android VM, never on Windows. The cleaner long-term source would be building the same services from AOSP `android-13.0.0_r*` (tag for `TQ3A.230901.001`)
for an arm64-only target. Microsoft's own images were checked and do not contain 64-bit versions of these; the Pixel 5 (`redfin`) factory image is multilib and also ships them as arm32.
