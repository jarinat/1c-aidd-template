@echo off
setlocal

if "%CLAUDE_PROJECT_DIR%"=="" (
  set "HOOK_SCRIPT=%~dp0block-inline-file-inspection.ps1"
) else (
  set "HOOK_SCRIPT=%CLAUDE_PROJECT_DIR%\.claude\hooks\block-inline-file-inspection.ps1"
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%HOOK_SCRIPT%"
exit /b %ERRORLEVEL%
