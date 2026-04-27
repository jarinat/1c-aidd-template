@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "SCRIPT_PATH=%~dp0new-guid.ps1"

if "%~1"=="" goto :default
if /I "%~1"=="help" goto :help
if /I "%~1"=="-Count" goto :count
goto :usage

:default
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%"
exit /b %ERRORLEVEL%

:help
if not "%~2"=="" goto :usage
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" help
exit /b %ERRORLEVEL%

:count
if "%~2"=="" goto :usage
if not "%~3"=="" goto :usage
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" -Count "%~2"
exit /b %ERRORLEVEL%

:usage
echo Usage:
echo   new-guid.cmd
echo   new-guid.cmd -Count ^<number^>
echo   new-guid.cmd help
exit /b 2
