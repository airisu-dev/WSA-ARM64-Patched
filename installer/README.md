# installer: how the WSA package is registered

`Install.bat` (starts `Install.ps1`, which elevates itself) and `Install.ps1` (registers the package folder with `Add-AppxPackage -Register`, installs the three
dependency `.appx`, and opens WSA Settings when done). `build.ps1` copies them, plus `LICENSE` as `LICENSE-installer-AGPL-3.0.txt`, into
the output folder. They are part of this repository and are not downloaded.

## Origin

Derived from the installer of [LSPosed/MagiskOnWSALocal @ `10659d90`](https://github.com/LSPosed/MagiskOnWSALocal/tree/10659d90b6133b3a3138fd780f272b6869346c39/installer)
(AGPL-3.0, Copyright LSPosed Contributors). The copyright line and the AGPL grant are kept in each file as the license requires.

| File | Upstream SHA-256 | Changes here |
|---|---|---|
| `Install.bat` (upstream name `Run.bat`) | `6df91942f27bf9b69d460795176980cd089fcfdcbdc7156ac90f85553dd007a4` | Header only; the logic is upstream's |
| `Install.ps1` | `c20ed36c80037de7999a12d648a334ae391fc153544c6c75ac69570f5e9948f5` | `Finish()` opens WSA Settings instead of the root-manager and Play Store apps; window titles and messages say "WSA" |
| `LICENSE` | `8486a10c4393cee1c25392769ddd3b2d6c242d6ec7928e1414efff7dfb2f07ef` | unchanged |

## Uninstall

`Uninstall.bat` (starts `Uninstall.ps1` elevated) is our own addition: it runs `wsaclient /shutdown` and `Remove-AppxPackage`. It deletes the Android data too; run `Uninstall.bat -KeepData` to preserve it. The shared dependencies, the Virtual Machine Platform feature and the package folder are left in place.
