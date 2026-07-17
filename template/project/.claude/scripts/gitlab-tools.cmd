@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_PATH=%SCRIPT_DIR%gitlab-tools.ps1"

if "%~1"=="" goto :usage

if /I "%~1"=="help" goto :run
if /I "%~1"=="threads" goto :run
if /I "%~1"=="pipeline" goto :run
if /I "%~1"=="pipeline-log" goto :run
if /I "%~1"=="reply" goto :run
if /I "%~1"=="resolve" goto :run
goto :usage

:run
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" %*
exit /b %ERRORLEVEL%

:usage
echo Usage:
echo   gitlab-tools.cmd help
echo.
echo Read commands:
echo   gitlab-tools.cmd threads -MrUrl ^<merge-request-url^> [-IncludeSystem]
echo   gitlab-tools.cmd pipeline -MrUrl ^<merge-request-url^>
echo   gitlab-tools.cmd pipeline-log -MrUrl ^<merge-request-url^> -JobId ^<job-id^> [-Tail ^<lines^>]
echo.
echo Write commands (always ask for permission):
echo   gitlab-tools.cmd reply -MrUrl ^<merge-request-url^> -DiscussionId ^<id^> -BodyFile ^<path^>
echo   gitlab-tools.cmd resolve -MrUrl ^<merge-request-url^> -DiscussionId ^<id^> [-Unresolve]
exit /b 2
