@echo off
rem Builds ThumbCrop.exe from ThumbCrop.cs with the C# compiler that ships with
rem Windows (.NET Framework 4). Nothing needs to be installed.
setlocal
set "CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" set "CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
if not exist "%CSC%" (
    echo [ERROR] The .NET Framework 4 C# compiler ^(csc.exe^) was not found.
    pause
    exit /b 1
)
echo Building ThumbCrop.exe ...
"%CSC%" /nologo /target:winexe /codepage:65001 /optimize+ /out:"%~dp0ThumbCrop.exe" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll "%~dp0ThumbCrop.cs"
if errorlevel 1 (
    echo [ERROR] Build failed.
    pause
    exit /b 1
)
echo Done: %~dp0ThumbCrop.exe
if /i not "%~1"=="/quiet" pause
exit /b 0
