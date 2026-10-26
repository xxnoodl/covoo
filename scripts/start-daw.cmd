@echo off
cd /d "%~dp0"
covoo-receiver.exe --serve --audio-device "CABLE Input (VB-Audio Virtual Cable)" --output "%~dp0recordings" %*
pause
