@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_PATH=%SCRIPT_DIR%gitlab-mr-review.ps1"

if "%~1"=="" goto :usage

if /I "%~1"=="help" goto :help
if /I "%~1"=="prepare" goto :prepare
if /I "%~1"=="cleanup" goto :cleanup
goto :usage

:help
if not "%~2"=="" goto :usage
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" help
exit /b %ERRORLEVEL%

:prepare
if /I not "%~2"=="-MrUrl" goto :usage
if "%~3"=="" goto :usage
if not "%~4"=="" goto :usage
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" prepare -MrUrl "%~3"
exit /b %ERRORLEVEL%

:cleanup
if /I not "%~2"=="-WorktreePath" goto :usage
if "%~3"=="" goto :usage
if not "%~4"=="" goto :usage
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" cleanup -WorktreePath "%~3"
exit /b %ERRORLEVEL%

:usage
echo Usage:
echo   gitlab-mr-review.cmd help
echo   gitlab-mr-review.cmd prepare -MrUrl ^<gitlab-merge-request-url^>
echo   gitlab-mr-review.cmd cleanup -WorktreePath ^<worktree-path^>
exit /b 2
