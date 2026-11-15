# Tooling, dependencies and gotchas

Handoff notes for anyone (or any session) debugging WSA on this kind of machine. Read [findings.md](findings.md)
for the reasoning; this file is about *how to work* without repeating known problems. Verified 2026-11-15 on a
Surface Pro 11 (Snapdragon X, Windows 11 26300, WSL 2.3.26) unless it says "untested".

## Environment

- **The Bash tool in this setup is an x86_64-emulated Git Bash** (`uname -m` = x86_64). Use PowerShell
  (`Get-CimInstance Win32_Processor`) to learn the real CPU. Bash also munges paths, which breaks `wsl` arguments.
- Not admin by default. Windows `sudo` runs in "Force New Window" mode, so its output does not come back: run elevated
  work as a script that redirects to a file (`sudo powershell -NoProfile -File x.ps1`). Nothing in this project
  actually needs elevation except `Install.bat` (installing the package).
- WSL distro: Debian 13 aarch64, used as `wsl -d Debian -u root -- ...` (no password needed). It must be
  **aarch64**: `build.ps1` checks.
- Python is only the Microsoft Store stub. `node` is available. 7-Zip/NanaZip reads VHDX/ext4/cpio read-only on
  the Windows side, but the build does not use it.

## What works and what does not

| Need | Status |
|---|---|
| `wsl --mount` of a VHDX | **Not supported on ARM64 Windows** (`WSL_E_WSL_MOUNT_NOT_SUPPORTED`). Edit images in Debian instead. |
| Edit guest images | `qemu-img convert` VHDX to raw, `debugfs -w` / `e2fsck` / `resize2fs`, convert back with `-O vhdx -o subformat=dynamic`. The result matches the originals' size and is accepted by WSA. |
| Compile native helpers | `gcc -static` in Debian produces arm64 Linux binaries. |
| Android-side tools from Magisk (`libmagiskpolicy.so`) | Bionic binaries; they **do not run on Debian**. Use libsepol (`tools\sepermissive.c`, link `libsepol.a`). |
| Scratch space | Work on WSL's own ext4 (`/root/...`); `/mnt/c` works but is far too slow for multi-GB images. |

## Gotchas

**Shell and quoting**
- Write a script file and run `wsl -d Debian -u root -- bash /mnt/c/.../x.sh` instead of `sh -c '...'`. Set
  `$env:WSL_UTF8 = 1`, otherwise `wsl` output is UTF-16.
- Backslashes are lost when a Windows path goes through `wsl.exe`, even to `wslpath`. Convert by hand
  (`C:\a\b` becomes `/mnt/c/a/b`, see `ToWsl` in `build.ps1`).
- Inside `wsl -- sh -c 'for n in ...; do cp ... $n ...'` the outer shell expands `$n` first and every command silently
  fails. Copy by explicit name and compare sizes afterwards.
- PowerShell mangles `|` and quotes in `adb shell '...'`: push a script to `/data/local/tmp` and run `sh script`.
- Never rely on exit statuses of `debugfs` (it exits 0 even when a file is missing or a write fails); parse its output
  or list the directory. `build-guest-images.sh` wraps this in `dfs`/`exists`/`label`/`install_file`.
- Do not hide stderr of build stages; a silent failure here means "deployed nothing, booted the old image".

**ext4 images**
- `debugfs rm` + `write` **drops the SELinux xattr**. Copy it with `ea_get -f` / `ea_set -f ... security.selinux`
  (labels carry a trailing NUL) and set `sif uid/gid/mode` explicitly.
- The vendor filesystem is ~99.7 % full; grow it (`truncate` + `e2fsck -f` + `resize2fs`) before adding files.
- Reading a live VHDX while the VM runs fails with `log needs to be replayed`. Stop WSA first, or you silently read the
  **previous** run's data.

**Windows side**
- Deploying files into a registered package needs WSA stopped (`wsaclient /shutdown`). `WsaService` retries a failing
  VM start about every 4 s and `WsaClient` keeps crashing; killing WSA processes was refused once by the permission
  classifier, so ask the user first.
- Launch with `Start-Process wsaclient -ArgumentList '/launch','wsa://com.android.settings'`
  (alias in `%LOCALAPPDATA%\Microsoft\WindowsApps`).
- Loose-registering a modified package (`Add-AppxPackage -Register`) requires removing `[Content_Types].xml`,
  `AppxBlockMap.xml`, `AppxSignature.p7x` and `AppxMetadata`; `build.ps1` does this.
- The live data disks are **not** the package's `userdata.vhdx`/`metadata.vhdx` (empty templates). They are
  `%LOCALAPPDATA%\Packages\MicrosoftCorporationII.WindowsSubsystemForAndroid_8wekyb3d8bbwe\LocalCache\{userdata,metadata}.2.vhdx`,
  128 GiB virtual and sparse. Per-boot logcat files under `LocalState\diagnostics\logcat` stay 0 bytes when the guest dies early.

## Guest facts useful for debugging

- Android 13, fingerprint `Windows/windows_arm64/windows_arm64:13/TQ3A.230901.001/2407.40000.4.0`, kernel
  `5.15.104-windows-subsystem-for-android-20230927+`.
- Boot chain: Hyper-V UEFI-like boot with `initrd=\initrd.img` → `wsainit` (WSL's init, Rust arm64, talks to the host over
  HvSocket) → execs `/system/init` (Android first stage: mounts metadata, vendor, system_ext, product; loads SELinux) →
  second stage. Vendor init script: `vendor/etc/init/init.windows_arm64.rc`.
- SCSI layout: `sda` system, `sdb` vendor, `sdc` system_ext, `sdd` product, `sde` userdata, `sdf` metadata.
- Kernel command line (built by the host, not editable from the package): `WSL_ROOT_INIT=1 panic=-1 nr_cpus=10
  console=hvc0 debug loglevel=7 androidboot.hardware=windows_arm64 androidboot.veritymode=enforcing
  androidboot.verifiedbootstate=green androidboot.fstab_suffix=2.windows swiotlb=noforce`.
- Benign init messages: `e2fsck` missing in first stage, `Failed to read vbmeta partitions`, `Apex SEPolicy failed
  signature check`, `/system/etc/selinux/apex/SEPolicy.zip` not found.
- A guest that reaches `sys.boot_completed` stays up; one that does not is killed by `WsaService` after ~126 s
  and restarted forever (the "Starting Windows Subsystem for Android" spinner).

## Seeing the guest log

| Situation | Method |
|---|---|
| Android is up (even if not booted) and Developer mode is on | `adb connect 127.0.0.1:58526`, then `adb logcat -d -b all -v threadtime`. Developer mode is a GUI toggle in WSA Settings (`Start-Process wsasettings`); the first connect says `unauthorized` until you tap **Allow** in a WSA window. The first thing to try. |
| Guest dies before logd starts | Early-boot logger: `tools\kmsglog.c` as `/init` of a custom initrd. It forks, then execs the real `wsainit`; the child copies `/dev/kmsg` to the last 1 MiB of the 128 GiB `userdata.2`/`metadata.2` disks (it only touches disks over 100 GiB, never the system images). Build with `tools\build-logger.sh`, pack with `node tools\mkcpio.js out.img init=kmsglog wsainit=wsainit`, deploy as `Tools\initrd.img`, launch, stop WSA, read back with `tools\readlog.sh`. |
| The logger stops at SELinux enforcement | The logger runs in the `kernel` domain and is denied after init enforces. Make `kernel` permissive in `vendor/etc/selinux/precompiled_sepolicy` (`tools\patch-all.sh kernel`, `tools\sepermissive.c`). This is debug-only: never ship it. The leftover 1 MiB at the end of the data disks is harmless. |

Sample captures: `tools\sample-guest-kmsg-*.txt`. `build-logger.sh` and `readlog.sh` have scratch paths from the
original session hard-coded; edit them before use. Untested idea: `%UserProfile%\.wslconfig` with `[wsl2] debugConsole=true`
or `kernelCommandLine=` (`wslcore.dll` contains those strings) would also affect the Debian VM.

## Driving the Android UI over ADB

Possible (`adb shell screencap -p /sdcard/x.png` + `adb pull`, `input tap X Y`, `input keyevent 4` = Back,
`dumpsys activity top`), with these caveats:

- WSA shows an app as a **freeform window** inside a 2880x1920 display (`dumpsys window windows`, line `Frames:`).
  `input tap` takes display coordinates; the view hierarchy is reported at a different scale (about 0.7), so do not mix
  the two. When the app fills the display, screenshot and tap coordinates map 1:1.
- **`screencap` can be stale** when the Windows window is occluded or minimised. Trust `dumpsys activity top` and
  `dumpsys window` for state, and bring the WSA window to the front before relying on a screenshot.
- `uiautomator dump` only sees WSA's `com.microsoft.windows.homeapp` placeholder window; it cannot see app controls.
- **The placeholder window can steal input focus** (`com.microsoft.windows.homeapp/.placeholder.PlaceholderActivity`).
  Check `dumpsys window | grep mCurrentFocus`; re-send the intent with the reorder flag
  (`am start -f 0x20000 -n <component> -a android.intent.action.VIEW -d <url>`) until the target app has focus.
- Verify results with `dumpsys` (`media.resource_manager`, `media.audio_flinger`, `activity`), not screenshots.
- WSA has no `.apk` file association; install with `adb install -r`. The guest has no browser of its own, and https links are routed to the
  Windows default browser by `com.microsoft.windows.userapp/BrowserIntentHandler`; side-load Firefox (arm64) if you need one.

## Apps used for testing

| App | Notes |
|---|---|
| Firefox (arm64) | Loads and plays youtube.com; no Google services needed. |
| NewPipe 0.29.3 | ExoPlayer; plays video in a native view with `c2.android.avc.decoder`. |
| YouTube Morphe 21.30.216 (`app.morphe.android.youtube`) + MicroG-RE 7.3.1 (`app.revanced.android.gms`) | Plays video. Install microG **before** first launching Morphe, otherwise clear its data (`pm clear`). microG coexists with the real Play Services (different package name). Morphe enables its own launcher alias on first start, which makes Android kill the process once; that is normal. |

Useful log lines: with microG missing, Morphe logs `GmsCore was not found`; with it, `Installed default security
provider GmsCore_OpenSSL`. `PhenotypeService ... Failed to find provider com.google.android.gms.phenotype` warnings are normal.
Debug aids for media: `dumpsys media.player`, `dumpsys media.resource_manager`, `dumpsys media.audio_flinger`.

## Research scripts

`tools\` holds the scripts and samples used during diagnosis. They are **not** part of the build and several have
hard-coded paths from the original session; see [tools/README.md](tools/README.md).
