@echo off
rem Remove the silent DSH autostart scheduled task.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-DshAutostart.ps1" -Uninstall
echo.
pause
