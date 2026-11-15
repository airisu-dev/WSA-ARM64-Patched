# What is inside the WSA package

WSA 2407.40000.4.0 is the last release before Microsoft discontinued it. Knowing the layers helps decide what can be
patched (this project) and what would have to be rebuilt (a from-scratch WSA).

| Layer | Files | Open-source equivalent |
|---|---|---|
| **Linux kernel** | `Tools\kernel`, `Tools\initrd.img` (only `/init` = `wsainit`, WSL's init) | Yes: `microsoft/WSA-Linux-Kernel` |
| **Android 13 OS** | `system.vhdx`, `vendor.vhdx`, `product.vhdx`, `system_ext.vhdx`, `userdata.vhdx`, `metadata.vhdx` (ext4 images) | Mostly AOSP; Microsoft's HALs in `vendor` are closed |
| **VM and hypervisor plumbing** | `wslcore.dll`, `wsldevicehost.dll`, `lxutil.dll`, `wslrelay.exe` | Partly: same idea as WSL2 (`microsoft/WSL`) |
| **Graphics** | `gfxstream_backend.dll`, `libEGL`/`libGLESv2` (ANGLE), `vulkan_dzn.dll` (Mesa Dozen: Vulkan on D3D12), `dxil.dll` | Yes: gfxstream (AOSP), ANGLE, Mesa |
| **Host service** | `WsaService\WsaService.exe` (starts the VM through the Host Compute Service) | No |
| **Window integration** | `WsaClient\WsaClient.exe` (each Android app becomes a Windows window) | No; WSLg (Weston + RDP RAIL) is the closest open design |
| **Settings, installer, packaging** | `WsaSettings.exe`, `CustomInstall\WsaSetup.exe`, `AppxManifest.xml` | Closed, but easy to rewrite (this project ships its own `Install.bat` / `Install.ps1`) |

The guest OS, kernel and graphics are open source or replaceable; the closed parts are the Windows-side service and the
window integration. So a "from scratch" WSA would mean rewriting those two, whereas patching the guest images (what
`..\build.ps1` does) keeps them as they are.

## Architecture in one paragraph

WSA is a Hyper-V lightweight VM started by `WsaService` through the Host Compute Service. It boots the 5.15.104
Linux kernel with `wsainit`, which hands over to Android's init. Android renders with gfxstream (Vulkan on D3D12 on the host),
and `WsaClient` maps every Android freeform task to its own Windows window. ADB is exposed at `127.0.0.1:58526` when Developer
mode is on. If Android does not reach `sys.boot_completed`, the host kills and restarts the guest after ~126 s.

## How to inspect the images (on ARM64 Windows)

`wsl --mount` is **not supported on ARM64 Windows**. Convert the VHDX to raw with `qemu-img` in a WSL distro and read it with
`debugfs` (`-w` to write). See [tooling-notes.md](tooling-notes.md). Useful things to read:

- `build.prop` (system and vendor, plus `/odm/etc/build.prop` inside `vendor.vhdx`): Android version, ABI lists, zygote.
- `vendor/etc/init/*.rc` and `vendor/lib64/hw/*`: Microsoft's services (graphics, input, clipboard, networking).
- the kernel config: `extract-ikconfig` on `Tools\kernel` (binder, virtio, Hyper-V vsock, dxgkrnl).

## Licensing

Microsoft's binaries and the Amazon Appstore bits are proprietary: use them as a reference, but do not redistribute modified
copies. The build here downloads Microsoft's package from a mirror, checks Microsoft's signature, and produces the patched
copy locally; see the trust section of `..\README.md`.
