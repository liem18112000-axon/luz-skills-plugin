@echo off
setlocal

set "SCRIPT_DIR=%~dp0"

where bash >nul 2>&1
if errorlevel 1 (
    echo [prepare] bash not found on PATH. Install Git for Windows ^(includes Git Bash^):
    echo            https://git-scm.com/download/win
    exit /b 1
)

bash "%SCRIPT_DIR%prepare.sh" %*
exit /b %errorlevel%
