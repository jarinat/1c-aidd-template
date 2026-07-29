@echo off
setlocal EnableExtensions DisableDelayedExpansion

pushd "%~dp0..\.." >nul || exit /b 1
oscript tools\scripts\download-sonar-issues.os %*
set "EXIT_CODE=%ERRORLEVEL%"
popd >nul
exit /b %EXIT_CODE%
