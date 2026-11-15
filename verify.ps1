<#
.SYNOPSIS
  Post-install checks for this WSA build (Snapdragon X / arm64). Prints PASS/FAIL per check, exits 1 if any FAIL.

.DESCRIPTION
  Needs WSA running with Developer mode ON and ADB authorised (README.md, "Install and first boot").
  Read-only except one tiny `cmd package compile` of a system app to prove the 64-bit dex2oat works.

.PARAMETER Adb      Path to adb.exe (default: the copy downloaded into .\deps\adb by download.ps1).
.PARAMETER Device   ADB address (default 127.0.0.1:58526).
.PARAMETER NoGapps  Skip the Google Play services / Play Store checks (builds without GApps).
#>
param(
  [string]$Adb = (Join-Path $PSScriptRoot 'deps\adb\platform-tools\adb.exe'),
  [string]$Device = '127.0.0.1:58526',
  [switch]$NoGapps
)
$ErrorActionPreference = 'Continue'
$fail = 0
function Check($name, [bool]$ok, $detail = '') {
  if ($ok) { Write-Host ("PASS  {0}  {1}" -f $name, $detail) -ForegroundColor Green }
  else     { Write-Host ("FAIL  {0}  {1}" -f $name, $detail) -ForegroundColor Red; $script:fail++ }
}
function Sh([string]$cmd) { (& $Adb -s $Device shell $cmd 2>&1 | Out-String).Trim() }
function Prop([string]$p) { Sh "getprop $p" }

# connect
& $Adb connect $Device 2>&1 | Out-Null
$state = (& $Adb -s $Device get-state 2>&1 | Out-String).Trim()
Check 'adb device reachable & authorised' ($state -eq 'device') "get-state=$state"
if ($state -ne 'device') { Write-Host "Cannot continue (turn on Developer mode, approve the debugging prompt)."; exit 1 }

# boot + SELinux
Check 'sys.boot_completed = 1'          ((Prop 'sys.boot_completed') -eq '1')
$enf = Sh 'getenforce'; Check 'SELinux Enforcing' ($enf -eq 'Enforcing') $enf

# 64-bit-only configuration
Check 'ro.zygote = zygote64'                 ((Prop 'ro.zygote') -eq 'zygote64')
Check 'abilist = arm64-v8a only'             ((Prop 'ro.product.cpu.abilist') -eq 'arm64-v8a')
Check 'abilist32 is empty'                   ((Prop 'ro.product.cpu.abilist32') -eq '')
Check 'debug.stagefright.ccodec = 4'         ((Prop 'debug.stagefright.ccodec') -eq '4')
Check 'dalvik.vm.dex2oat64.enabled = true'   ((Prop 'dalvik.vm.dex2oat64.enabled') -eq 'true')
if (-not $NoGapps) { Check 'ro.com.google.gmsversion set' ((Prop 'ro.com.google.gmsversion') -ne '') (Prop 'ro.com.google.gmsversion') }

# media services (these were the 32-bit crash loops)
foreach ($s in 'media','drm','mediaextractor','media.swcodec','audioserver','android-hardware-media-c2-goldfish-hal-1-0') {
  Check "service $s running" ((Prop "init.svc.$s") -eq 'running')
}
$ps = Sh 'ps -A'
foreach ($p in 'android.hardware.audio.service','android.hardware.cas@1.2-service','mediaserver','drmserver') {
  Check "process $p present" ($ps -match [regex]::Escape($p))
}

# logs: no 32-bit exec / link failures in this boot
$log = (& $Adb -s $Device logcat -d -b all 2>&1 | Out-String)
$ef = ([regex]::Matches($log, 'Exec format')).Count
Check 'no "Exec format error" in log'  ($ef -eq 0) "count=$ef"
$cl = ([regex]::Matches($log, 'CANNOT LINK')).Count
Check 'no "CANNOT LINK" in log'        ($cl -eq 0) "count=$cl"
$kd = ([regex]::Matches($log, 'avc:\s+denied.*scontext=u:r:kernel')).Count
Check 'no kernel-domain SELinux denials (debug logger absent)' ($kd -eq 0) "count=$kd"

# codecs advertised
$mp = Sh 'dumpsys media.player'
$dec = ([regex]::Matches($mp, 'Decoder "c2\.android')).Count
Check 'software decoders advertised (>= 10)' ($dec -ge 10) "c2.android decoders=$dec"
Check 'H.264 decoder present' ($mp -match 'c2\.android\.avc\.decoder')

# Google apps
if (-not $NoGapps) {
  $pk = Sh 'pm list packages'
  foreach ($p in 'com.android.vending','com.google.android.gms','com.google.android.gsf') { Check "package $p" ($pk -match [regex]::Escape($p)) }
}

# 64-bit dex2oat actually works (installd used to run the arm32 dex2oat32 and fail)
& $Adb -s $Device logcat -c 2>&1 | Out-Null
Sh 'cmd package compile -m speed -f com.android.externalstorage' | Out-Null
Start-Sleep 3
$log2 = (& $Adb -s $Device logcat -d -b all 2>&1 | Out-String)
Check 'dexopt runs dex2oat64'  ($log2 -match 'bin/dex2oat64')
Check 'no dex2oat32 failure'   ($log2 -notmatch 'dex2oat32\) failed')

Write-Host ""
if ($fail -eq 0) { Write-Host "ALL CHECKS PASSED" -ForegroundColor Green; exit 0 }
else { Write-Host "$fail CHECK(S) FAILED" -ForegroundColor Red; exit 1 }
