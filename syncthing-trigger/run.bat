@echo off
title Syncthing Sync Trigger
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Sync-Trigger.ps1"
echo.
echo Exit code: %errorlevel%
pause
