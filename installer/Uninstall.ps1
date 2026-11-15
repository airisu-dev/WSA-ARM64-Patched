# Uninstalls Windows Subsystem for Android (the package registered by Install.ps1) for the current user.
# By default the Android data (installed apps, accounts, files) is deleted too; use -KeepData to preserve it.
# The shared dependencies (VCLibs, UI.Xaml) and the Virtual Machine Platform feature are left in place.
param([switch]$KeepData)

$Host.UI.RawUI.WindowTitle = "Uninstalling WSA...."
$Name = "MicrosoftCorporationII.WindowsSubsystemForAndroid"

If (-Not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $ps = If (Get-Command pwsh.exe -ErrorAction SilentlyContinue) { "pwsh.exe" } Else { "powershell.exe" }
    $extra = If ($KeepData) { " -KeepData" } Else { "" }
    $Proc = Start-Process -PassThru -Verb RunAs $ps -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"$extra"
    If ($null -Ne $Proc) { $Proc.WaitForExit() }
    exit
}

$Installed = Get-AppxPackage -Name $Name
If ($null -Eq $Installed) {
    Write-Output "WSA is not installed for this user. Nothing to do."
}
Else {
    Write-Output "Found $($Installed.PackageFullName)"
    # stop the VM first; ignore errors if the client is not running
    Try { Start-Process wsaclient -ArgumentList "/shutdown" -Wait -ErrorAction Stop } Catch { }
    Start-Sleep -Seconds 3
    Try {
        If ($KeepData) { Remove-AppxPackage -PreserveApplicationData -Package $Installed.PackageFullName -ErrorAction Stop }
        Else { Remove-AppxPackage -Package $Installed.PackageFullName -ErrorAction Stop }
        Write-Output "WSA was uninstalled$(If ($KeepData) { ' (Android data kept)' } Else { ' (Android data removed)' })."
        Write-Output "The package files in this folder were not deleted; remove the folder yourself if you no longer need it."
    }
    Catch {
        Write-Error "Uninstall failed: $_"
    }
}
Write-Output "Press any key to exit"
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
