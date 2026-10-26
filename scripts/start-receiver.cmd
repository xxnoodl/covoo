@echo off
cd /d "%~dp0"
covoo-receiver.exe --serve --output "%~dp0recordings" %*
pause
