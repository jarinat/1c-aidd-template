@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_PATH=%SCRIPT_DIR%gitlab-mr-review.ps1"

if "%~1"=="" goto :usage

if /I "%~1"=="help" goto :help
if /I "%~1"=="prepare" goto :prepare
if /I "%~1"=="cleanup" goto :cleanup
if /I "%~1"=="show-file" goto :show_file
if /I "%~1"=="grep-file" goto :grep_file
if /I "%~1"=="list-files" goto :list_files
if /I "%~1"=="grep-tree" goto :grep_tree
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

:show_file
if /I not "%~2"=="-WorktreePath" goto :usage
if "%~3"=="" goto :usage
if /I not "%~4"=="-Ref" goto :usage
if "%~5"=="" goto :usage
if /I not "%~6"=="-RepoPath" goto :usage
if "%~7"=="" goto :usage
if not "%~8"=="" goto :usage
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" show-file -WorktreePath "%~3" -Ref "%~5" -RepoPath "%~7"
exit /b %ERRORLEVEL%

:grep_file
if /I not "%~2"=="-WorktreePath" goto :usage
if "%~3"=="" goto :usage
if /I not "%~4"=="-Ref" goto :usage
if "%~5"=="" goto :usage
if /I not "%~6"=="-RepoPath" goto :usage
if "%~7"=="" goto :usage
if /I not "%~8"=="-Pattern" goto :usage
if "%~9"=="" goto :usage
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" grep-file -WorktreePath "%~3" -Ref "%~5" -RepoPath "%~7" -Pattern "%~9"
exit /b %ERRORLEVEL%

:list_files
if /I not "%~2"=="-WorktreePath" goto :usage
if "%~3"=="" goto :usage
if /I not "%~4"=="-Ref" goto :usage
if "%~5"=="" goto :usage
if /I not "%~6"=="-RepoPath" goto :usage
if "%~7"=="" goto :usage
if not "%~8"=="" goto :usage
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" list-files -WorktreePath "%~3" -Ref "%~5" -RepoPath "%~7"
exit /b %ERRORLEVEL%

:grep_tree
if /I not "%~2"=="-WorktreePath" goto :usage
if "%~3"=="" goto :usage
if /I not "%~4"=="-Ref" goto :usage
if "%~5"=="" goto :usage
if /I not "%~6"=="-Pattern" goto :usage
if "%~7"=="" goto :usage
if not "%~8"=="" goto :usage
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" grep-tree -WorktreePath "%~3" -Ref "%~5" -Pattern "%~7"
exit /b %ERRORLEVEL%

:usage
echo Usage:
echo   gitlab-mr-review.cmd help
echo   gitlab-mr-review.cmd prepare -MrUrl ^<gitlab-merge-request-url^>
echo   gitlab-mr-review.cmd cleanup -WorktreePath ^<worktree-path^>
echo   gitlab-mr-review.cmd show-file -WorktreePath ^<worktree-path^> -Ref ^<sha-or-ref^> -RepoPath ^<repo-relative-path^>
echo   gitlab-mr-review.cmd grep-file -WorktreePath ^<worktree-path^> -Ref ^<sha-or-ref^> -RepoPath ^<repo-relative-path^> -Pattern ^<regex^>
echo   gitlab-mr-review.cmd list-files -WorktreePath ^<worktree-path^> -Ref ^<sha-or-ref^> -RepoPath ^<repo-relative-prefix^>
echo   gitlab-mr-review.cmd grep-tree -WorktreePath ^<worktree-path^> -Ref ^<sha-or-ref^> -Pattern ^<regex^>
exit /b 2
