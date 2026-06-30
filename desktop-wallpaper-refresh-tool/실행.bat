@echo off
title Wallpaper Fix
echo Re-applying desktop wallpaper...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Refresh-Wallpaper.ps1"
pause
