# Findings: why WSA fails on Snapdragon X, and what fixes it

Status: **solved and reproducible.** The recipe that applies every fix below is `..\build.ps1`; this
document explains *why* each change exists and how it was found. Verified 2026-11-15 on a Surface Pro 11
(Snapdragon X X1P64100, Windows 11 26300, WSL 2.3.26 with Debian 13 aarch64), package
`MicrosoftCorporationII.WindowsSubsystemForAndroid` 2407.40000.4.0 (arm64, Android 13).
Upstream report: https://github.com/MustardChef/WSABuilds/issues/325

Contents: [Summary](#summary) Â· [Root cause](#root-cause) Â· [The changes](#the-changes-and-the-reason-for-each) Â·
[How it was diagnosed](#how-it-was-diagnosed) Â· [Verified behaviour](#verified-behaviour) Â·
[Known limits](#known-limits-and-open-items) Â· [Disproved theories](#disproved-theories-do-not-repeat-these)

## Summary

| Symptom | Cause | Fix (build step) |
|---|---|---|
| Guest powers off ~4 s after start; `WsaClient` crashes `0xc0000409`, `StartNewSession` times out | Snapdragon X cannot execute AArch32. `boringssl_self_test32_vendor` fails with `Exec format error` and has `reboot_on_failure` | Remove every 32-bit ABI property so the trigger never fires (change 1) |
| Guest stays up but "Starting Windows Subsystem for Android" never ends; restarts every ~126 s | Audio/CAS/DRM/media/OMX launchers are 32-bit and crash-loop, so Android never reaches `sys.boot_completed` | Replace them with arm64 builds, drop the OMX HAL (changes 2, 3) |
| Apps list no video decoders | `debug.stagefright.ccodec=0` turns Codec2 off, and the OMX HAL is gone | `ccodec=4` (change 4) |
| No app is ever AOT-compiled | `installd` runs the 32-bit `dex2oat32` | `dalvik.vm.dex2oat64.enabled=true` (change 5) |
| Play Store / Play Services wanted | Not in the Microsoft image; Magisk is *not* required | Bake MindTheGapps into `product`/`system_ext` (change 6) |
| With the Play Store installed, `system_server` crash-loops and the client sits on "Starting..." forever | Android allows exactly one package verifier; the Play Store adds a second | `extra\component-overrides.xml` (change 7) |

Two symptoms look identical from Windows ("Starting..." forever or a crashing `WsaClient`) but have different
causes, so always check the guest-side log (see [tooling-notes.md](tooling-notes.md)) before guessing.

## Root cause

The guest kernel is fine on Snapdragon X (GICv3, PSCI 1.1, 10 CPUs, Hyper-V enlightenments all come up).
Android's first-stage init runs, loads SELinux and starts the second stage. Then:

```
init: processing action (ro.product.cpu.abilist32=* && early-init) from (/vendor/etc/init/boringssl_self_test.rc:2)
init: starting service 'boringssl_self_test32_vendor'...
init: cannot execv('/vendor/bin/boringssl_self_test32'). ...: Exec format error
init: Service with 'reboot_on_failure' option failed, shutting down system.
init: Got shutdown_command 'reboot,boringssl-self-check-failed'
```

The Oryon cores have no AArch32 mode at EL0, so any 32-bit ARM binary fails with `Exec format error`.
Older Snapdragons (8cx, SQ1) still run AArch32, which is why the stock arm64 package works there.
Hyper-V reports the resulting clean guest power-off as event 18508; `WsaClient` then times out waiting for the VM.

Gotcha: the trigger `ro.product.cpu.abilist32=*` also matches a property that is set to an **empty** value.
The property must be *deleted*, in all three places (system, vendor and the `odm` build.prop inside
`vendor.vhdx`); missing one keeps the 32-bit ABI alive.

## The changes, and the reason for each

All changes are made to the four guest images; the Windows-side binaries, the kernel and Microsoft's
`Tools\initrd.img` are untouched. The SELinux policy is unmodified. Implemented in
`..\scripts\build-guest-images.sh`.

1. **64-bit-only properties.** `ro.zygote=zygote64`; the three `ro.*.product.cpu.abilist` lists set to
   `arm64-v8a`; the three `abilist32` properties deleted. Stops `boringssl_self_test32*` and the secondary zygote.
2. **64-bit launchers and libraries.** After change 1 the guest survives, but five services crash-loop with
   `Exec format error` because their executables are arm32 (the 64-bit HAL implementations in `vendor/lib64`
   already exist; only the small launchers are 32-bit):

   | Service | Binary |
   |---|---|
   | `vendor.audio-hal` | `/vendor/bin/hw/android.hardware.audio.service` |
   | `vendor.cas-hal-1-2` | `/vendor/bin/hw/android.hardware.cas@1.2-service` |
   | `drm` | `/system/bin/drmserver` |
   | `media` | `/system/bin/mediaserver` |
   | `vendor.media.omx` | `/vendor/bin/hw/android.hardware.media.omx@1.0-service` |

   `audioserver` is killed each time the audio HAL restarts, so AudioFlinger never stays up and Android never
   reports `boot_completed`; the host watchdog then kills the guest after ~126 s and restarts it.
   The arm64 builds come from the `snickler/WSA-Patched` 0.0.2 images and are tracked byte-for-byte in `..\donor\`
   (32 files, SHA-256 in `donor\MANIFEST.tsv`, provenance in `donor\README.md`). Three libraries
   (`libmediaplayerservice`, `libresourcemanagerservice`, `libstagefright_httplive`) exist only as 32-bit in
   `/system/lib` in Microsoft's image, so the 64-bit `mediaserver` cannot link without them
   (`CANNOT LINK EXECUTABLE ... library "libmediaplayerservice.so" not found`).
3. **OMX HAL replaced by Codec2.** The OMX HAL launcher and its `.rc` are removed; the donor's arm64
   `android.hardware.media.c2@1.0-service-goldfish` plus a VINTF manifest listing `IComponentStore@1.1` take over.
   The vendor filesystem is ~99.7 % full, so it is grown to 256 MiB first (product to 512 MiB, system_ext to 256 MiB).
4. **`debug.stagefright.ccodec=4`.** The stock value `0` disables Codec2; without this the device advertises no
   decoders at all ("Decoder infos" empty). With it the software Codec2 store (`com.android.media.swcodec`) provides
   `c2.android.{avc,vp8,vp9,aac,mp3,opus,vorbis,flac,...}.decoder`. All decoders are software-only; that is enough
   for playback (see [Disproved theories](#disproved-theories-do-not-repeat-these)).
5. **`dalvik.vm.dex2oat64.enabled=true`** in `system/build.prop`. Otherwise `installd` runs
   `/apex/com.android.art/bin/dex2oat32` even for arm64 packages and every dexopt fails.
6. **Google apps without Magisk.** MindTheGapps 13 arm64 provides Play Store (`Phonesky`), Play Services
   (`GmsCore`) and Services Framework. A minimal set of files is copied into `product` and `system_ext` with
   explicit SELinux labels. Velvet, speech services, TalkBack, GooglePartnerSetup and all overlays are skipped
   on purpose (a `GoogleWebViewOverlay` would redirect the WebView provider to a WebView that is not installed).
   `ro.com.google.gmsversion=13_202304` only takes effect from the **system** build.prop.
7. **`extra\component-overrides.xml` is mandatory.** WSA's package verifier is Microsoft's
   `com.microsoft.windows.userapp`; the Play Store declares a second `PackageVerificationReceiver`. Android
   requires exactly one, so `system_server` dies at startup (`RuntimeException: There must be exactly one verifier`),
   restarts every ~5 s, and the guest is killed after ~126 s. MindTheGapps does not ship the override file
   (the LSPosed WSA add-on used by MagiskOnWSALocal does); ours disables that receiver and the stock OTA components.
   Replacing the permission with `<deny-permission>` in the privapp allow-list does *not* help.
8. **Amazon Appstore removed** (`apex\mado*.apex`) by default; `-KeepAmazon` keeps it (untested).

## How it was diagnosed

Condensed, because the order matters when repeating this on a new device:

1. **Host side only tells you the VM dies.** `WsaClient` crashes with `0xc0000409` in `ucrtbase.dll`; Hyper-V-Worker
   shows the guest resetting or shutting down within seconds. `0xC0370103` on "Create/Start compute system" is
   logged even for healthy starts and is not an error signal.
2. **Android-level logs do not exist for early failures.** Per-boot logcat files in `LocalState\diagnostics\logcat`
   stay 0 bytes, and the data disk is never mounted. `wsl --mount` does not work on ARM64 Windows, so images are
   edited and read with `qemu-img` + `debugfs` in a WSL distro.
3. **A tiny kernel-log capture** (`tools\kmsglog.c`, used as `/init` in a custom initrd, then handing over to
   `wsainit`) writes `/dev/kmsg` to the tail of the 128 GiB data disks. It stops at SELinux enforcement, because the
   logger runs in the `kernel` domain. Making `kernel` permissive in `vendor/etc/selinux/precompiled_sepolicy`
   (`tools\sepermissive.c`, libsepol) let init's second stage log everything, which exposed the
   `boringssl_self_test32` failure.
4. **Once 64-bit init survives, use ADB.** Enable Developer mode in WSA Settings; ADB listens on
   `127.0.0.1:58526` and `adb logcat` shows the real causes (the `CANNOT LINK` error, the verifier exception). The init
   log alone cannot show them.
5. **Reference build.** `snickler/WSA-Patched` 0.0.2 (reported to boot on arm64, with buggy audio and no video) was
   compared read-only against Microsoft's images. It changed exactly the binaries found crash-looping above, spoofed
   the device identity as a Pixel 5, removed the 32-bit libraries, and left `ccodec=0`, which explains its "no video".
   That comparison confirmed the diagnosis independently; the build here imports only its 32 arm64 files and keeps
   Microsoft's SELinux policy and build identity.

## Verified behaviour

The final build passes `..\verify.ps1` (29 checks): `sys.boot_completed=1`, SELinux **Enforcing**, one VM start with
no reset, no `Exec format` / `CANNOT LINK` / kernel denials, audio/CAS/Codec2 HALs, `drmserver`, `mediaserver` and
`media.swcodec` running, 15 software decoders (H.264 included), Play Store / Play Services / Services Framework
installed with their processes up, `dex2oat64` used for `cmd package compile`. The Microsoft images, kernel and data
templates in the downloaded bundle are byte-identical to the originals backed up from the earlier install, and Microsoft's own
`Tools\initrd.img` boots (its `/init` is the same `wsainit` binary), so no custom initrd is needed.

Playback checks: Firefox, NewPipe (ExoPlayer, `c2.android.avc.decoder`) and YouTube Morphe all play video;
audio tracks are active in AudioFlinger; the guest has internet. Play Services completed a Google check-in and the
Play Store self-updated.

## Known limits and open items

- **32-bit-only apps cannot run** (no 32-bit zygote or libraries). This is inherent to the CPU.
- **Play Store sign-in is untested.** The device is not Play Protect certified; sign-in may require registering the
  GSF ID at https://www.google.com/android/uncertified/ (not readable over plain adb). Play Integrity / SafetyNet
  will fail, so apps that require it (banking, some streaming) may refuse to run; that would need Magisk-style modules.
- Play Store runtime permissions are not auto-granted on top of an existing userdata; grant them when prompted.
- Camera, microphone (AudioRecord denied for apps) and Bluetooth are untested or not working.
- The 64-bit launchers come from an unsigned third-party release; an arm64-only AOSP build of
  `android-13.0.0_r*` (`TQ3A.230901.001`) would be a better long-term source. The Pixel 5 (`redfin`) factory image is
  **not** an alternative: it is multilib and its launchers are arm32 too.
- The original MagiskOnWSALocal initrd (Magisk + embedded GApps) reset the guest after ~2 s on this CPU. This was
  not investigated further, because Magisk is not needed.
- Not tested: `-KeepAmazon`, registering the output with `Install.bat` (needs UAC) on a clean machine, fetching the
  package directly from Microsoft's service.
- Worth sharing upstream (issue #325): the 32-bit `boringssl_self_test32` + `reboot_on_failure`, then the 32-bit
  media/audio launchers, the libraries that exist only in `/system/lib`, `ccodec=0`, `dex2oat32` and the verifier conflict.

## Disproved theories (do not repeat these)

| Theory | What was actually true |
|---|---|
| A kernel/CPU mismatch on Oryon kills the guest | The 5.15.104 kernel boots cleanly on Snapdragon X. |
| The 32-bit hypothesis is wrong because emptying `abilist32` changed nothing | The test was flawed: an empty property still matches the trigger, and the `odm` copy was missed. |
| Hyper-V result `0xC0370103` marks the failure | It also appears for healthy starts. |
| The Pixel 5 `redfin` image has 64-bit launchers | It is multilib with arm32 launchers; "redfin" is only the spoofed identity in snickler's build. |
| YouTube Morphe rejects software-only decoders (`canH264Main.0`, `progressive.fmt.noneavailable`) | The failure came from app state cached by a first launch **before** microG was installed. After `pm clear` or a reinstall the same APK plays, and the app then uses `c2.android.avc.decoder`. Install microG first, or clear the app afterwards. |
| The package here was Microsoft's stock package | The earlier install was a MagiskOnWSALocal build (patched initrd with Magisk and embedded GApps). Microsoft's original `initrd.img` contains only `/init` (= `wsainit`). |
| `needed.sh` showed all dependent libraries present | `debugfs stat` exits 0 even when the file is missing; always parse its output. |
| Magisk is required for Google Play | Magisk only delivered the GApps module; baking the same apps into the images works. |
| `<deny-permission>` for the verifier permission fixes the verifier conflict | The verifier set is not filtered by that permission; the receiver must be disabled via `component-overrides.xml`. |
