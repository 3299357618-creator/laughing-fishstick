@echo off
rem Install silent DSH autostart for ALL users (asks for administrator via UAC).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-DshAutostart.ps1" -AllUsers
echo.
pause
