@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -STA -File "%~dp0desktop.ps1"
if errorlevel 1 pause
