@echo off
rem Install silent DSH autostart for the CURRENT user (no admin rights needed).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-DshAutostart.ps1"
echo.
pause
