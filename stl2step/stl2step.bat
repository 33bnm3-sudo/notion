@echo off
chcp 65001 >nul
setlocal
title STL to STEP 변환기

rem ------------------------------------------------------------
rem  사용법: STL 파일을 이 파일 아이콘 위로 끌어다 놓으세요. 여러 개도 됩니다.
rem  같은 폴더에 같은 이름의 .step 파일이 만들어집니다.
rem
rem  변환 로직(stl2step_core.py)은 실행할 때마다 GitHub 에서 최신 버전을 받아 씁니다.
rem  인터넷이 안 되면 마지막으로 받아 둔 버전을 씁니다.
rem
rem  FreeCAD를 자동으로 못 찾으면, 아래 줄의 FC= 뒤에
rem  freecadcmd.exe 의 전체 경로를 직접 적어 주세요.
rem  예: set "FC=C:\Program Files\FreeCAD 1.0\bin\freecadcmd.exe"
rem ------------------------------------------------------------
set "FC="
set "CORE_URL=https://raw.githubusercontent.com/33bnm3-sudo/notion/HEAD/stl2step/stl2step_core.py"

rem === FreeCAD 위치 자동으로 찾기 ===
if defined FC goto :found
for /d %%D in ("%ProgramFiles%\FreeCAD*" "%LocalAppData%\Programs\FreeCAD*" "%LocalAppData%\FreeCAD*") do (
  if exist "%%~D\bin\freecadcmd.exe" set "FC=%%~D\bin\freecadcmd.exe"
)
if defined FC goto :found
for /f "delims=" %%P in ('where freecadcmd.exe 2^>nul') do set "FC=%%P"
if defined FC goto :found
goto :nofc

:found
if not exist "%FC%" goto :nofc

rem === 파일 없이 더블클릭한 경우 ===
if "%~1"=="" goto :usage

rem === 작업 폴더 (한글 경로 문제를 피하려고 영문 경로에서 작업) ===
set "W=%PUBLIC%\stl2step"
if not exist "%W%" mkdir "%W%"
set "CORE=%W%\stl2step_core.py"
set "STL2STEP_IN=%W%\in.stl"
set "STL2STEP_OUT=%W%\out.step"

rem === GitHub 에서 최신 변환 로직 받기 ===
if exist "%W%\core_new.py" del "%W%\core_new.py"
curl.exe -fsSL --max-time 20 -o "%W%\core_new.py" "%CORE_URL%" >nul 2>&1
if not exist "%W%\core_new.py" powershell -NoProfile -Command "try { Invoke-WebRequest -UseBasicParsing -TimeoutSec 20 -Uri '%CORE_URL%' -OutFile '%W%\core_new.py' } catch {}" >nul 2>&1
if not exist "%W%\core_new.py" goto :nodownload
for %%A in ("%W%\core_new.py") do if %%~zA LSS 1000 goto :nodownload
move /y "%W%\core_new.py" "%CORE%" >nul
echo.
echo  변환 로직: GitHub 최신 버전
goto :coreok

:nodownload
if exist "%W%\core_new.py" del "%W%\core_new.py"
if not exist "%CORE%" goto :nocore
echo.
echo  [알림] GitHub 에 연결하지 못해서, 마지막으로 받아 둔 변환 로직을 씁니다.

:coreok
echo  사용하는 FreeCAD: "%FC%"
echo.

:next
if "%~1"=="" goto :end
call :convert "%~1"
shift
goto :next

:end
echo.
echo  모두 끝났습니다.
echo.
pause
exit /b 0

rem === 파일 하나 변환 ===
:convert
if /i not "%~x1"==".stl" goto :notstl
echo  변환 중: "%~nx1"
if exist "%STL2STEP_OUT%" del "%STL2STEP_OUT%"
copy /y "%~f1" "%STL2STEP_IN%" >nul
"%FC%" "%CORE%" <nul >"%W%\log.txt" 2>&1
if not exist "%STL2STEP_OUT%" goto :failed
move /y "%STL2STEP_OUT%" "%~dpn1.step" >nul
echo     저장: "%~n1.step"
echo.
exit /b
:failed
echo     실패했습니다. 기록 파일: "%W%\log.txt"
echo.
exit /b
:notstl
echo  건너뜀 - STL 파일이 아님: "%~nx1"
exit /b

:usage
echo.
echo  STL 파일을 이 아이콘 위로 끌어다 놓으면 STEP으로 바꿔 드려요.
echo  여러 개를 한꺼번에 끌어다 놓아도 됩니다.
echo.
pause
exit /b 0

:nocore
echo.
echo  [오류] GitHub 에서 변환 로직을 받지 못했고, 받아 둔 것도 없습니다.
echo  인터넷 연결을 확인한 뒤 다시 실행해 주세요.
echo.
pause
exit /b 1

:nofc
echo.
echo  [오류] FreeCAD를 찾지 못했습니다.
echo  이 파일을 마우스 오른쪽 클릭 - 편집 으로 메모장에서 열고,
echo  set "FC=" 줄에 freecadcmd.exe 경로를 적어 주세요.
echo.
pause
exit /b 1
