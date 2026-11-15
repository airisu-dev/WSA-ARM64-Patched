<#
.SYNOPSIS
  Interactive cleanup of what download.ps1 and build.ps1 generate, so the next run starts clean. Developer helper.

.DESCRIPTION
  Scans for generated data and shows a checklist (only what exists, with sizes):
    deps\            everything download.ps1 fetched (bundle, MindTheGapps, dependency .appx, adb)
    work\            build.ps1 scratch (normally already removed after a successful build)
    *.part           interrupted downloads
    <distro>         /root/wsa-build in EVERY installed WSL distro (raw images, several GB)
    WSA_*\           the build output folder(s)
  Keys:  Up/Down move   Space check/uncheck   A check/uncheck all   Enter remove the checked items   Esc or Q cancel
  Nothing is checked at first. Never touches the tracked files (donor, installer, extra, scripts, docs, *.ps1, README.md).
  An output folder that is the registered WSA install location is kept (run its Uninstall.bat first).
  Scanning starts any stopped WSL distro for a moment (it runs `du` as root inside it).

.PARAMETER All     Remove everything found, without the checklist.
.PARAMETER DryRun  Show what would be removed; delete nothing.
#>
[CmdletBinding()]
param([switch]$All, [switch]$DryRun)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$env:WSL_UTF8 = 1

function MB([string[]]$paths) {
  $sum = 0
  foreach ($p in $paths) { if (Test-Path -LiteralPath $p) { $sum += (Get-ChildItem -LiteralPath $p -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum } }
  [math]::Round($sum / 1MB)
}
function Remove-Inside([string]$p) {
  $full = [IO.Path]::GetFullPath($p)
  if (-not $full.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "refusing to remove outside the build folder: $full" }
  if (-not (Test-Path -LiteralPath $full)) { return }
  if ($DryRun) { Write-Host "[dry run] would remove $full"; return }
  Remove-Item -LiteralPath $full -Recurse -Force; Write-Host "removed $full"
}

# ---- scan ----------------------------------------------------------------------------------------------------------
Write-Host "Scanning $root ..."
$installed = Get-AppxPackage -Name MicrosoftCorporationII.WindowsSubsystemForAndroid -ErrorAction SilentlyContinue
$items = New-Object System.Collections.Generic.List[object]
function Add-Item([string]$Label, [long]$Size, [string]$Kind, $Arg) {
  $items.Add([pscustomobject]@{ Label = $Label; Size = $Size; Kind = $Kind; Arg = $Arg; Checked = $false })
}
function Invoke-Item($it) {
  switch ($it.Kind) {
    'path' { foreach ($x in $it.Arg) { Remove-Inside $x } }
    'wsl'  { if ($DryRun) { Write-Host "[dry run] would remove $($it.Arg):/root/wsa-build" }
             else { & wsl.exe -d $it.Arg -u root -- rm -rf /root/wsa-build; Write-Host "removed $($it.Arg):/root/wsa-build" } }
    'out'  { if ($installed -and ([IO.Path]::GetFullPath($installed.InstallLocation).TrimEnd('\') -ieq [IO.Path]::GetFullPath($it.Arg).TrimEnd('\'))) {
               Write-Warning "$($it.Arg) is the registered WSA install location; kept. Run its Uninstall.bat first." }
             else { Remove-Inside $it.Arg } }
  }
}

if (Test-Path "$root\deps") { Add-Item 'deps\  (downloads)' (MB @("$root\deps")) 'path' @("$root\deps") }
if (Test-Path "$root\work") { Add-Item 'work\  (build scratch)' (MB @("$root\work")) 'path' @("$root\work") }
$parts = @(Get-ChildItem $root -Recurse -Force -Filter *.part -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notlike "$root\WSA_*" } | ForEach-Object FullName)
if ($parts.Count) { Add-Item '*.part  (interrupted downloads)' (MB $parts) 'path' $parts }

$distros = @((& wsl.exe -l -q 2>$null) -replace "`0", '' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
foreach ($d in $distros) {
  $o = & wsl.exe -d $d -u root -- sh -c 'test -d /root/wsa-build && du -sm /root/wsa-build | cut -f1' 2>$null
  if ("$o" -match '^\s*(\d+)') { Add-Item "WSL scratch  ${d}:/root/wsa-build" ([long]$Matches[1]) 'wsl' $d }
}
foreach ($out in @(Get-ChildItem $root -Directory -Filter 'WSA_*' | ForEach-Object FullName)) {
  Add-Item ("build output  " + (Split-Path $out -Leaf)) (MB @($out)) 'out' $out
}
if ($items.Count -eq 0) { Write-Host 'Nothing to clean.'; exit 0 }
# ---- choose --------------------------------------------------------------------------------------------------------
if ($All) { $items | ForEach-Object { $_.Checked = $true } }
else {
  $interactive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected
  if (-not $interactive) { throw "not an interactive console; use -All (optionally with -DryRun)" }
  Write-Host
  Write-Host 'Up/Down move   Space check   A all   Enter remove checked   Esc cancel' -ForegroundColor DarkGray
  $top = [Console]::CursorTop; $cur = 0
  $height = $items.Count + 1
  # make room so the list never scrolls while redrawing
  1..$height | ForEach-Object { Write-Host }
  $top = [Math]::Max(0, [Console]::CursorTop - $height)
  [Console]::CursorVisible = $false
  try {
    while ($true) {
      [Console]::SetCursorPosition(0, $top)
      for ($i = 0; $i -lt $items.Count; $i++) {
        $it = $items[$i]; $box = if ($it.Checked) { '[x]' } else { '[ ]' }; $ptr = if ($i -eq $cur) { '>' } else { ' ' }
        $line = ('{0} {1} {2,-48} {3,7} MB' -f $ptr, $box, $it.Label, $it.Size)
        Write-Host ($line.PadRight([Console]::WindowWidth - 1)) -ForegroundColor $(if ($i -eq $cur) { 'Cyan' } else { 'Gray' })
      }
      $n = ($items | Where-Object Checked).Count
      Write-Host (("  {0} of {1} checked" -f $n, $items.Count).PadRight([Console]::WindowWidth - 1)) -ForegroundColor DarkGray
      $k = [Console]::ReadKey($true)
      switch ($k.Key) {
        'UpArrow'   { $cur = ($cur - 1 + $items.Count) % $items.Count }
        'DownArrow' { $cur = ($cur + 1) % $items.Count }
        'Spacebar'  { $items[$cur].Checked = -not $items[$cur].Checked }
        'A'         { $all = -not ($items | Where-Object { -not $_.Checked }); $items | ForEach-Object { $_.Checked = -not $all } }
        'Enter'     { break }
        'Escape'    { $items | ForEach-Object { $_.Checked = $false }; $cancel = $true; break }
        'Q'         { $items | ForEach-Object { $_.Checked = $false }; $cancel = $true; break }
      }
      if ($k.Key -in 'Enter', 'Escape', 'Q') { break }
    }
  } finally { [Console]::CursorVisible = $true }
  Write-Host
  if ($cancel -or -not ($items | Where-Object Checked)) { Write-Host 'Nothing removed.'; exit 0 }
}

# ---- remove --------------------------------------------------------------------------------------------------------
foreach ($it in ($items | Where-Object Checked)) { Invoke-Item $it }
Write-Host "`nDone."
exit 0
