@echo off
title Edge Remover Launcher
echo Requesting administrator rights...
echo A UAC prompt should appear - click Yes.
echo.

powershell -NoProfile -Command "Start-Process powershell -ArgumentList '-NoExit -NoProfile -ExecutionPolicy Bypass -File \"%~dp0Remove-Edge.ps1\"' -Verb RunAs" 2>nul

if %errorlevel% neq 0 (
    echo.
    echo FAILED to launch - the UAC prompt may have been cancelled, or PowerShell could not start.
) else (
    echo.
    echo Launch requested. Look for a NEW blue PowerShell window - that is where the actual removal runs.
    echo If no new window appeared and no UAC prompt showed up, something blocked it - take a screenshot of this window.
)

echo.
echo This launcher window will stay open. Press any key to close it.
pause >nul
