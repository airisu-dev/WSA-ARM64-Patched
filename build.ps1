<#
.SYNOPSIS
  Build the WSA package (.\WSA_<version>_arm64) from the files in .\deps. No network access.

.DESCRIPTION
  1  extract the arm64 package from the Microsoft bundle                       -> work\payload
  2  unpack the MindTheGapps zip                                                -> work\gapps
  3  build the four patched Android images in WSL Debian (scripts\build-guest-images.sh), using the
     donor\MANIFEST.tsv: the 64-bit files are extracted from Google's emulator image in deps\donor                      -> work\images
  4  assemble the package folder: Microsoft payload + patched images + dependency .appx + our installer\
Inputs: .\deps (download.ps1) and the tracked .\donor, .\extra and .\installer (tracked in this folder). Run download.ps1 first. Afterwards run <output>\Install.bat (admin) to install (Uninstall.bat removes it), then verify.ps1.

.PARAMETER Distro       WSL distribution used for the image build (default Debian, must be aarch64).
.PARAMETER Force        Replace an existing output folder.
.PARAMETER KeepWork     Keep .\work and the WSL scratch directory (several GB) after a successful build.
.PARAMETER KeepAmazon   Keep Microsoft's apex\mado_release.apex (Amazon Appstore). The tested build removes it (default).
#>
[CmdletBinding()]
param([string]$Distro = 'Debian', [switch]$Force, [switch]$KeepWork, [switch]$KeepAmazon)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$root = $PSScriptRoot; $deps = "$root\deps"; $work = "$root\work"
$gzip = "$deps\donor\arm64-v8a-33_r02.zip"   # Google's Android 13 arm64 emulator image: source of the 64-bit files
$env:WSL_UTF8 = 1

function Step($m) { Write-Host "`n== $m" -ForegroundColor Cyan }
# C:\a\b -> /mnt/c/a/b. Done by hand: passing a backslash path through wsl.exe (even to wslpath) loses the backslashes.
function ToWsl([string]$p) {
  $full = [IO.Path]::GetFullPath($p)
  if ($full -notmatch '^([A-Za-z]):\\') { throw "not a local drive path: $full" }
  '/mnt/' + $Matches[1].ToLower() + '/' + $full.Substring(3).Replace('\', '/')
}
function Need([string]$p) { if (-not (Test-Path -LiteralPath $p)) { throw "missing $p`nRun .\download.ps1 first." } }
function Extract-Entry([string]$Zip, [string]$Pattern, [string]$Dest) {
  $z = [IO.Compression.ZipFile]::OpenRead($Zip)
  try { $e = $z.Entries | Where-Object { $_.FullName -match $Pattern } | Select-Object -First 1
        if (-not $e) { throw "no entry matching $Pattern in $Zip" }
        [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $Dest, $true) } finally { $z.Dispose() }
}

# ---- preflight -----------------------------------------------------------------------------------------------------
Step "preflight"
$bundle = Get-ChildItem "$deps\msix" -Filter *.Msixbundle -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $bundle) { throw "no *.Msixbundle in $deps\msix. Run .\download.ps1 first." }
# The bundle comes from a third-party mirror; Microsoft's own signature on it must still verify.
$sig = Get-AuthenticodeSignature -FilePath $bundle.FullName
if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch '^CN=Microsoft Corporation,') {
  throw "bundle is not validly signed by Microsoft Corporation (status: $($sig.Status))"
}
Write-Host "bundle signature: $($sig.Status), $($sig.SignerCertificate.Subject)"
$gappsZip = Get-ChildItem "$deps\gapps" -Filter MindTheGapps-*.zip | Select-Object -First 1; if (-not $gappsZip) { throw "no MindTheGapps zip in $deps\gapps" }
foreach ($f in 'Microsoft.UI.Xaml.2.8_arm64.appx','Microsoft.VCLibs.140.00_arm64.appx','Microsoft.VCLibs.140.00.UWPDesktop_arm64.appx') { Need "$deps\appx\$f" }
# tracked in this folder (not downloaded)
Need $gzip
foreach ($f in 'donor\MANIFEST.tsv','donor\vintf-manifest.xml','scripts\lp_extract.py','extra\component-overrides.xml','installer\Install.bat','installer\Install.ps1','installer\Uninstall.bat','installer\Uninstall.ps1','installer\LICENSE') { if (-not (Test-Path "$root\$f")) { throw "missing $root\$f (it is part of the repository)" } }
& wsl.exe -d $Distro -u root -- uname -m 2>&1 | ForEach-Object { if ($_ -notmatch 'aarch64') { throw "WSL distro '$Distro' must be aarch64 (got: $_). Install with: wsl --install -d Debian" } }
Write-Host "bundle $($bundle.Name)`nWSL    $Distro (aarch64)"

# ---- 1. payload ----------------------------------------------------------------------------------------------------
Step "1/4 extract the arm64 package from the bundle"
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory -Force "$work\bundle","$work\gapps","$work\images" | Out-Null
Extract-Entry $bundle.FullName '^WsaPackage_.*_ARM64_Release-Nightly\.msix$' "$work\bundle\arm64.msix"
[IO.Compression.ZipFile]::ExtractToDirectory("$work\bundle\arm64.msix", "$work\payload")
Remove-Item "$work\bundle" -Recurse -Force
[xml]$man = Get-Content "$work\payload\AppxManifest.xml"
$id = $man.Package.Identity
if ($id.ProcessorArchitecture -ne 'arm64') { throw "payload is $($id.ProcessorArchitecture), expected arm64" }
$out = "$root\WSA_$($id.Version)_arm64"
Write-Host "package $($id.Name) $($id.Version) $($id.ProcessorArchitecture)  ->  $out"
if ((Test-Path $out) -and (Get-ChildItem $out -Force | Measure-Object).Count -gt 0) { if ($Force) { Get-ChildItem $out -Force | Remove-Item -Recurse -Force } else { throw "output exists: $out (use -Force or remove it)" } }
foreach ($n in 'system','vendor','product','system_ext','userdata','metadata') { Need "$work\payload\$n.vhdx" }
Need "$work\payload\Tools\kernel"; Need "$work\payload\Tools\initrd.img"

# ---- 2. gapps ------------------------------------------------------------------------------------------------------
Step "2/4 unpack the Google apps"
[IO.Compression.ZipFile]::ExtractToDirectory($gappsZip.FullName, "$work\gapps")

# ---- 3. guest images (WSL) -----------------------------------------------------------------------------------------
Step "3/4 build the patched Android images in WSL ($Distro). This takes several minutes."
$sh = ToWsl "$root\scripts\build-guest-images.sh"
& wsl.exe -d $Distro -u root -- bash $sh (ToWsl "$work\payload") (ToWsl "$root\donor") (ToWsl $gzip) (ToWsl "$work\gapps") (ToWsl "$root\extra") (ToWsl "$work\images")
if ($LASTEXITCODE -ne 0) { throw "guest image build failed (exit $LASTEXITCODE)" }
foreach ($n in 'system','vendor','product','system_ext') { Need "$work\images\$n.vhdx" }

# ---- 4. assemble ---------------------------------------------------------------------------------------------------
Step "4/4 assemble $out"
New-Item -ItemType Directory -Force $out | Out-Null
# Microsoft payload, minus: the 4 images (replaced), and the package signature/block map (a modified loose-registered package cannot keep them)
robocopy "$work\payload" $out /E /NFL /NDL /NJH /NJS /NP /XD AppxMetadata /XF system.vhdx vendor.vhdx product.vhdx system_ext.vhdx AppxBlockMap.xml AppxSignature.p7x '[Content_Types].xml' | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE)" }
foreach ($n in 'system','vendor','product','system_ext') { Copy-Item "$work\images\$n.vhdx" "$out\$n.vhdx" }
if (-not $KeepAmazon) { Remove-Item "$out\apex\mado*.apex" -Force -ErrorAction SilentlyContinue }   # Amazon Appstore (what the tested build does)
foreach ($f in 'Microsoft.UI.Xaml.2.8_arm64.appx','Microsoft.VCLibs.140.00_arm64.appx','Microsoft.VCLibs.140.00.UWPDesktop_arm64.appx') { Copy-Item "$deps\appx\$f" "$out\$f" }
# our installer (tracked in .\installer; AGPL-3.0, see installer\README.md)
Copy-Item "$root\installer\Install.bat"   "$out\Install.bat"
Copy-Item "$root\installer\Uninstall.bat" "$out\Uninstall.bat"
Copy-Item "$root\installer\Uninstall.ps1" "$out\Uninstall.ps1"
Copy-Item "$root\installer\Install.ps1" "$out\Install.ps1"
Copy-Item "$root\installer\LICENSE"     "$out\LICENSE-installer-AGPL-3.0.txt"
$utf8 = New-Object Text.UTF8Encoding $false

# filelist.txt: Install.ps1 refuses to run if a listed top-level entry is missing
$names = @(Get-ChildItem $out -Force | Select-Object -ExpandProperty Name) + 'filelist.txt' | Sort-Object -Unique
[IO.File]::WriteAllText("$out\filelist.txt", (($names -join "`n") + "`n"), $utf8)
$missing = Get-Content "$out\filelist.txt" | Where-Object { -not (Test-Path "$out\$_") }
if ($missing) { throw "filelist.txt names missing files: $($missing -join ', ')" }

Write-Host "`nimages in the package:"
Get-ChildItem $out -Filter *.vhdx | ForEach-Object { '  {0,-16} {1,9:N0} bytes   sha256 {2}' -f $_.Name, $_.Length, (Get-FileHash $_.FullName).Hash.Substring(0,16).ToLower() }
'  {0,-16} {1,9:N0} bytes   sha256 {2}   (Microsoft original, untouched)' -f 'Tools\initrd.img', (Get-Item "$out\Tools\initrd.img").Length, (Get-FileHash "$out\Tools\initrd.img").Hash.Substring(0,16).ToLower()

if (-not $KeepWork) {
  Remove-Item $work -Recurse -Force
  & wsl.exe -d $Distro -u root -- rm -rf /root/wsa-build
}
Write-Host "`nBuild complete: $out" -ForegroundColor Green
Write-Host "Next: stop WSA if running (wsaclient /shutdown), then run '$out\Install.bat' (UAC prompt), then .\verify.ps1"
exit 0
