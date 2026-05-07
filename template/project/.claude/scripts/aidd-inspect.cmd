@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_PATH=%SCRIPT_DIR%aidd-inspect.ps1"

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" %*
