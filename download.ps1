<#
.SYNOPSIS
  Download every dependency of the build into .\deps (idempotent: a file that already matches its SHA-256 is skipped).

.DESCRIPTION
  This is the ONLY step that touches the internet. build.ps1 uses just the files under .\deps.
  Every pinned file is verified against the SHA-256 below; a mismatch aborts.
  See README.md ("Dependencies and references") for where each file comes from. The installer scripts and the donor manifest
  are NOT downloaded: they are tracked in this folder (.\installer, .\donor).

.PARAMETER SkipAdb         Do not download Google's platform-tools (only verify.ps1 needs adb).
.PARAMETER KeepArchives    Keep the big intermediate archives (NuGet package, winget bundle) after extracting the .appx files.
#>
[CmdletBinding()]
param([switch]$SkipAdb, [switch]$KeepArchives)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$deps = Join-Path $PSScriptRoot 'deps'

function Sha256([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLower() }

function Get-Verified {
  param([string]$Name, [string]$Url, [string]$Path, [string]$Sha256)
  if ((Test-Path -LiteralPath $Path) -and ((Sha256 $Path) -eq $Sha256)) { Write-Host ("  OK (cached)  {0}" -f $Name); return }
  New-Item -ItemType Directory -Force (Split-Path $Path) | Out-Null
  $part = "$Path.part"
  Write-Host ("  downloading  {0}" -f $Name)
  & curl.exe -L --fail --silent --show-error --retry 3 --retry-delay 3 -C - -o $part $Url
  if ($LASTEXITCODE -ne 0) { throw "download failed ($LASTEXITCODE): $Url" }
  $got = Sha256 $part
  if ($got -ne $Sha256) { Remove-Item $part -Force; throw "SHA-256 mismatch for $Name`n  expected $Sha256`n  got      $got" }
  Move-Item -LiteralPath $part -Destination $Path -Force
  Write-Host ("  OK           {0}" -f $Name)
}

function Expand-ZipEntry {   # extract the single entry matching $Pattern (regex on the entry's full name) to $Dest
  param([string]$Zip, [string]$Pattern, [string]$Dest)
  $z = [IO.Compression.ZipFile]::OpenRead($Zip)
  try {
    $e = $z.Entries | Where-Object { $_.FullName -match $Pattern } | Select-Object -First 1
    if (-not $e) { throw "no entry matching '$Pattern' in $Zip" }
    [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $Dest, $true)
  } finally { $z.Dispose() }
}

function Get-AppxIdentity([string]$Appx) {
  $z = [IO.Compression.ZipFile]::OpenRead($Appx)
  try {
    $r = New-Object IO.StreamReader(($z.Entries | Where-Object FullName -eq 'AppxManifest.xml').Open())
    [xml]$x = $r.ReadToEnd(); $r.Dispose()
    $x.Package.Identity
  } finally { $z.Dispose() }
}

Write-Host "`n[1/5] WSA 2407.40000.4.0 bundle (MustardChef/WSAPackages)"
Get-Verified 'WSA msixbundle' `
  'https://github.com/MustardChef/WSAPackages/releases/download/WSA_2407.40000.4.0/MicrosoftCorporationII.WindowsSubsystemForAndroid_2407.40000.4.0_neutral_._8wekyb3d8bbwe.Msixbundle' `
  "$deps\msix\MicrosoftCorporationII.WindowsSubsystemForAndroid_2407.40000.4.0_neutral_._8wekyb3d8bbwe.Msixbundle" `
  'ca1a91cf272ec3ea1f226f0a8d7ac12669ef2148c74961ae04e90167d6792b92'

Write-Host "`n[2/5] Google apps (MindTheGapps 13.0.0 arm64)"
Get-Verified 'MindTheGapps zip' `
  'https://github.com/MindTheGapps/13.0.0-arm64/releases/download/MindTheGapps-13.0.0-arm64-20231025_200931/MindTheGapps-13.0.0-arm64-20231025_200931.zip' `
  "$deps\gapps\MindTheGapps-13.0.0-arm64-20231025_200931.zip" `
  '3ff2edaa75406eb4214402fca6906d4b413ab50afdb1af033d9e396992338d0b'

Write-Host "`n[3/5] Dependency packages for WSA (arm64): UI.Xaml 2.8, VCLibs 140.00, VCLibs 140.00 UWPDesktop"
New-Item -ItemType Directory -Force "$deps\appx" | Out-Null
$appx = @(
  @{ File='Microsoft.UI.Xaml.2.8_arm64.appx';                  Sha='052ab1507191902467340a3856be4a77c3a6ad51a7a33cae54cc1f5c813e500a'; Min='8.2208.12001.0' },
  @{ File='Microsoft.VCLibs.140.00_arm64.appx';                Sha='c73d0f55dda331f9dcbefc99ff5a420b62120773d2917387639382aa478533ee'; Min='14.0.33519.0' },
  @{ File='Microsoft.VCLibs.140.00.UWPDesktop_arm64.appx';     Sha='831118f2f5cac8e29284e4ecc23bf4236436ccc2ea4a7c225c4946f8cfd29dd3'; Min='14.0.33728.0' }
)
$need = $appx | Where-Object { -not ((Test-Path "$deps\appx\$($_.File)") -and ((Sha256 "$deps\appx\$($_.File)") -eq $_.Sha)) }
if ($need) {
  $arch = "$deps\appx\_archives"; New-Item -ItemType Directory -Force $arch | Out-Null
  if ($need.File -contains 'Microsoft.UI.Xaml.2.8_arm64.appx') {
    # NuGet package Microsoft.UI.Xaml 2.8.7 (Microsoft). The appx inside is tools/AppX/arm64/Release/Microsoft.UI.Xaml.2.8.appx
    Get-Verified 'Microsoft.UI.Xaml 2.8.7 nupkg' 'https://api.nuget.org/v3-flatcontainer/microsoft.ui.xaml/2.8.7/microsoft.ui.xaml.2.8.7.nupkg' `
      "$arch\microsoft.ui.xaml.2.8.7.nupkg" '79207b10fe243eb1a8dcdc29beceba2f472f145ed31f147f7ae3f43b0659c9f7'
    Expand-ZipEntry "$arch\microsoft.ui.xaml.2.8.7.nupkg" '^tools/AppX/arm64/Release/Microsoft\.UI\.Xaml\.2\.8\.appx$' "$deps\appx\Microsoft.UI.Xaml.2.8_arm64.appx"
  }
  if ($need.File -match 'VCLibs') {
    # microsoft/winget-cli v1.29.380 DesktopAppInstaller_Dependencies.zip (Microsoft) ships both VCLibs packages for arm64
    Get-Verified 'winget-cli v1.29.380 dependency bundle' 'https://github.com/microsoft/winget-cli/releases/download/v1.29.380/DesktopAppInstaller_Dependencies.zip' `
      "$arch\DesktopAppInstaller_Dependencies.zip" 'ba875afe9d190f61218985ac0292a99d1db710bf93e13c68944ca9d89f0d82d1'
    Expand-ZipEntry "$arch\DesktopAppInstaller_Dependencies.zip" '^arm64/Microsoft\.VCLibs\.140\.00_14\.0\.33519\.0_arm64\.appx$'            "$deps\appx\Microsoft.VCLibs.140.00_arm64.appx"
    Expand-ZipEntry "$arch\DesktopAppInstaller_Dependencies.zip" '^arm64/Microsoft\.VCLibs\.140\.00\.UWPDesktop_14\.0\.33728\.0_arm64\.appx$' "$deps\appx\Microsoft.VCLibs.140.00.UWPDesktop_arm64.appx"
  }
  if (-not $KeepArchives) { Remove-Item $arch -Recurse -Force }
}
foreach ($a in $appx) {
  $p = "$deps\appx\$($a.File)"
  if ((Sha256 $p) -ne $a.Sha) { throw "SHA-256 mismatch: $($a.File)" }
  $id = Get-AppxIdentity $p
  if ($id.ProcessorArchitecture -ne 'arm64') { throw "$($a.File) is not arm64" }
  if ([version]$id.Version -lt [version]$a.Min) { throw "$($a.File) version $($id.Version) < required $($a.Min)" }
  Write-Host ("  OK           {0}  {1}" -f $a.File, $id.Version)
}

Write-Host "`n[4/5] adb (Google platform-tools), only used by verify.ps1"
if ($SkipAdb) { Write-Host "  skipped (-SkipAdb)" }
elseif (Test-Path "$deps\adb\platform-tools\adb.exe") { Write-Host "  OK (cached)  platform-tools" }
else {
  New-Item -ItemType Directory -Force "$deps\adb" | Out-Null
  $zip = "$deps\adb\platform-tools-latest-windows.zip"
  Write-Host "  downloading  platform-tools (latest; not pinned by hash, Google only publishes 'latest' under this URL)"
  & curl.exe -L --fail --silent --show-error --retry 3 -o $zip 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip'
  if ($LASTEXITCODE -ne 0) { throw "platform-tools download failed" }
  [IO.Compression.ZipFile]::ExtractToDirectory($zip, "$deps\adb")
  Remove-Item $zip -Force
  Write-Host ("  OK           {0}" -f ((& "$deps\adb\platform-tools\adb.exe" version) -join ' ' ))
}

Write-Host "`n[5/5] 64-bit Android binaries: Google's Android 13 arm64 emulator system image (672 MB; the build extracts 31 files from it)"
Get-Verified 'arm64-v8a-33_r02.zip' `
  'https://dl.google.com/android/repository/sys-img/android/arm64-v8a-33_r02.zip' `
  "$deps\donor\arm64-v8a-33_r02.zip" `
  '55ba9a20d473dd5351c77342016956342c40375f3e073b65a43dc9db13ccc5c6'
Write-Host "`nAll dependencies are in $deps"
exit 0
