@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 > nul

set "SCRIPT_PATH=%~dp0http-smoke.ps1"

if "%~1"=="" goto :usage
if /I "%~1"=="help" goto :help
if /I "%~1"=="run"  goto :passthrough

goto :usage

:passthrough
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" %*
exit /b %ERRORLEVEL%

:help
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" help
exit /b %ERRORLEVEL%

:usage
echo Usage:
echo   http-smoke.cmd run -Profile ^<name^> -EndpointPath ^<path^> [-Method GET^|POST^|...]
echo                      [-ConfigFile ^<path^>] [-Url ^<url^> ^| -BaseUrl ^<url^>]
echo                      [-BodyFile ^<path^> ^| -Body ^<inline-json^>]
echo                      [-ExpectedStatus 200,400] [-ExpectedSubstring ^<text^>]
echo   http-smoke.cmd help
exit /b 2

