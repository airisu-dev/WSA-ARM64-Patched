# donor: where the 64-bit Android binaries come from

Microsoft's WSA ships a few Android services only as 32-bit ARM executables, and the Snapdragon X cannot run those. The build replaces
them with 64-bit (AArch64) builds taken from **Google's official Android 13 arm64 emulator system image**. No binary is stored in this repository:
`download.ps1` fetches the image, `build-guest-images.sh` extracts the files and checks every one against its SHA-256 before installing it.

## Files in this folder

| File | Purpose |
|---|---|
| `MANIFEST.tsv` | The 32 files to install: image, path in the image, mode, SELinux label, SHA-256, size, label source, kind, **source** |
| `vintf-manifest.xml` | Our trimmed `/vendor/etc/vintf/manifest.xml` (the OMX entry swapped for the Codec2 one). Google has no counterpart, so this one comes from the repository |

`source` is `google` (same path inside Google's image), `google:<path>` (another path there; used once, for the `lib64/hw` copy of
`android.hardware.cas.native@1.0.so`, which Google ships only in `/lib64`), or `repo:<file>` (a file in this folder). `label_source = keep` means the build keeps the
SELinux label of the file it replaces in Microsoft's image (`vintf/manifest.xml`, `drmserver`, `mediaserver`) instead of the recorded one.

## The Google image

| | |
|---|---|
| Package | `system-images;android-33;default;arm64-v8a`, revision 2 (AOSP build `TE1A.220922.034`, `userdebug`, signed with the public AOSP test keys) |
| URL | https://dl.google.com/android/repository/sys-img/android/arm64-v8a-33_r02.zip (672,331,372 bytes) |
| SHA-256 | `55ba9a20d473dd5351c77342016956342c40375f3e073b65a43dc9db13ccc5c6` (pinned in `download.ps1`; SHA-1 `69883e92b77f8705af135ee86e1d87589f8f113e` is published in Google's `sys-img2-3.xml`) |
| Used parts | `vendor.img` (GPT, ext4 in partition 1) and `system.img` (GPT; partition 2 is a dynamic-partition `super` image holding `system`, `system_ext`, `product` and `vendor` as linear extents) |

`scripts\lp_extract.py` (plain Python 3, no `lpunpack` needed) copies the `vendor` filesystem and parses the `super` metadata to copy out the `system` filesystem;
the files are then read with `debugfs`.

## What is taken

| From | Files | Notes |
|---|---|---|
| `vendor/bin/hw/` | `android.hardware.audio.service`, `android.hardware.cas@1.2-service`, `android.hardware.media.c2@1.0-service-goldfish` | the 64-bit HAL launchers (audio, CAS, Codec2) that replace Microsoft's arm32 ones |
| `vendor/etc/` | the Codec2 service `.rc`, its seccomp policy | `vintf/manifest.xml` is ours (see above) |
| `vendor/lib64/` | 21 libraries (CAS, Codec2, goldfish software decoders, minijail, bufferpool) | 64-bit counterparts the new HALs link against |
| `system/system/bin/` | `drmserver`, `mediaserver` | 64-bit builds of the two arm32 media services |
| `system/system/lib64/` | `libmediaplayerservice.so`, `libresourcemanagerservice.so`, `libstagefright_httplive.so` | these exist only as 32-bit in Microsoft's `/system/lib`, so the 64-bit `mediaserver` could not link |

## Integrity and provenance

- The zip is verified by SHA-256 after download; every extracted file is verified again against `MANIFEST.tsv`, and the build stops on a mismatch.
- Every executable and library is a 64-bit ARM ELF (`class 2`, machine `0xB7`); they run only inside the Android VM, never on Windows.
- The files used to come from the community build `snickler/WSA-Patched` 0.0.2. They are byte-identical to Google's, so Google's image replaced it as the source:
  an official, checksummed download instead of an unsigned third-party release. A build with the files taken from Google's image was boot-, `verify.ps1`- and audio-tested.
- Microsoft's own images were checked and do not contain 64-bit versions of these; the Pixel 5 (`redfin`) factory image is multilib and ships them as arm32.
- Licensing: AOSP-derived, mostly Apache-2.0, and they keep their own licenses; they are downloaded, not redistributed here.