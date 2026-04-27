@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_PATH=%SCRIPT_DIR%gitlab-mr-review.ps1"

if "%~1"=="" goto :usage

if /I "%~1"=="help" goto :run
if /I "%~1"=="prepare" goto :run
if /I "%~1"=="cleanup" goto :run
if /I "%~1"=="show-file" goto :run
if /I "%~1"=="grep-file" goto :run
if /I "%~1"=="list-files" goto :run
if /I "%~1"=="grep-tree" goto :run
goto :usage

:run
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" %*
exit /b %ERRORLEVEL%

:usage
echo Usage:
echo   gitlab-mr-review.cmd help
echo   gitlab-mr-review.cmd prepare -MrUrl ^<gitlab-merge-request-url^>
echo   gitlab-mr-review.cmd cleanup -WorktreePath ^<worktree-path^>
echo   gitlab-mr-review.cmd show-file -WorktreePath ^<worktree-path^> -Ref ^<sha-or-ref^> -RepoPath ^<repo-relative-path^>
echo   gitlab-mr-review.cmd grep-file -WorktreePath ^<worktree-path^> -Ref ^<sha-or-ref^> -RepoPath ^<repo-relative-path^> -Pattern ^<regex^> [-First ^<count^>]
echo   gitlab-mr-review.cmd list-files -WorktreePath ^<worktree-path^> -Ref ^<sha-or-ref^> -RepoPath ^<repo-relative-prefix^>
echo   gitlab-mr-review.cmd grep-tree -WorktreePath ^<worktree-path^> -Ref ^<sha-or-ref^> -Pattern ^<regex^> [-RepoPath ^<repo-relative-prefix^>] [-First ^<count^>]
exit /b 2
