@echo off
chcp 65001 >nul
cd /d "%~dp0"

where python >nul 2>nul
if errorlevel 1 (
    echo Python이 설치되어 있지 않습니다. https://www.python.org 에서 설치 후 다시 실행해주세요.
    pause
    exit /b 1
)

echo 필요한 패키지를 확인/설치합니다...
python -m pip install -r requirements.txt --quiet

echo.
python download_video.py

pause
