@echo off
rem Drag image files onto this file (or onto the desktop shortcut that
rem install-shortcut.bat creates) to open them in the crop editor. Double-click to open an empty editor.
rem Builds ThumbCrop.exe first if it is missing or older than ThumbCrop.cs.
setlocal
set "NEWEST="
for /f "delims=" %%F in ('dir /b /o:d "%~dp0ThumbCrop.*" 2^>nul') do set "NEWEST=%%F"
if /i not "%NEWEST%"=="ThumbCrop.exe" (
    call "%~dp0build.bat" /quiet
    if errorlevel 1 exit /b 1
)
start "" "%~dp0ThumbCrop.exe" %*
