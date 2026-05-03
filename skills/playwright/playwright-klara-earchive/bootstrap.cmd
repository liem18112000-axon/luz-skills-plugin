@echo off
REM bootstrap.cmd - verify deps for playwright-klara-earchive on Windows.
REM Idempotent: safe to call at the start of every skill invocation.
REM Exit 0 = all deps present (or installed in-process). Exit 1 = manual action required.

setlocal EnableDelayedExpansion
set "SKILL_DIR=%~dp0"
set "SKILL_DIR=%SKILL_DIR:~0,-1%"
for %%I in ("%SKILL_DIR%\..") do set "SKILLS_ROOT=%%~fI"
set "MISSING="

call :have node
if errorlevel 1 (
    echo [bootstrap] node not found - attempting `winget install OpenJS.NodeJS.LTS` 1>&2
    where winget >nul 2>nul
    if errorlevel 1 (
        set "MISSING=!MISSING!|node - install from https://nodejs.org/"
    ) else (
        winget install -e --id OpenJS.NodeJS.LTS --silent --accept-source-agreements --accept-package-agreements >nul 2>nul
        call :have node
        if errorlevel 1 set "MISSING=!MISSING!|node - winget install failed; install manually from https://nodejs.org/"
    )
)

call :have gcloud
if errorlevel 1 (
    echo [bootstrap] gcloud not found - auto-install skipped (interactive auth required) 1>&2
    set "MISSING=!MISSING!|gcloud - install from https://cloud.google.com/sdk/docs/install, then run: gcloud auth login"
)

if not exist "%SKILLS_ROOT%\luz-skill-flow-logs\SKILL.md" (
    set "MISSING=!MISSING!|sibling skill 'luz-skill-flow-logs' - expected at %SKILLS_ROOT%\luz-skill-flow-logs\"
)

if defined MISSING (
    echo [bootstrap] MISSING dependencies - manual action required: 1>&2
    for %%M in ("!MISSING:|=" "!") do (
        if not "%%~M"=="" echo   - %%~M 1>&2
    )
    echo [bootstrap] After installing, re-invoke the skill. 1>&2
    exit /b 1
)

echo [bootstrap] all deps present 1>&2
exit /b 0

:have
where %1 >nul 2>nul
exit /b %errorlevel%
