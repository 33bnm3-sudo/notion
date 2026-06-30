@echo off
chcp 65001 >nul
title Windows 10 우클릭 메뉴 복원 도구
:menu
cls
echo ============================================
echo   Windows 10 스타일 우클릭 메뉴 복원 도구
echo ============================================
echo.
echo  1. Windows 10 스타일 메뉴로 변경
echo  2. Windows 11 기본 메뉴로 복원
echo  3. 종료
echo.
set /p choice="번호를 선택하세요: "

if "%choice%"=="1" goto classic
if "%choice%"=="2" goto win11
if "%choice%"=="3" goto end
goto menu

:classic
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Set-ClassicContextMenu.ps1" -Mode Classic
pause
goto menu

:win11
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Set-ClassicContextMenu.ps1" -Mode Windows11
pause
goto menu

:end
exit
