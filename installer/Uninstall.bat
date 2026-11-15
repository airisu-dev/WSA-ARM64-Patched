:: WSA uninstall launcher (fresh-build): starts Uninstall.ps1. Pass -KeepData to keep the Android apps' data.
@echo off
%~d0
cd "%~dp0"
if not exist Uninstall.ps1 (
    echo "Uninstall.ps1" is not found.
    echo Press any key to exit
    pause>nul
    exit 1
) else (
    start powershell.exe -ExecutionPolicy Bypass -File .\Uninstall.ps1 %*
    exit
)
