@echo off
cd /d "%~dp0"
covoo-receiver.exe --serve --audio-device "CABLE Input (VB-Audio Virtual Cable)" --buffer-ms 8 --device-buffer-frames 128 --output "%~dp0recordings" %*
pause
