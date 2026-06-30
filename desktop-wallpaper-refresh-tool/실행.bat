@echo off
chcp 65001 >nul
title 바탕화면 검은 화면 복구 도구
echo 바탕화면 배경화면을 다시 적용합니다...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Refresh-Wallpaper.ps1"
pause
