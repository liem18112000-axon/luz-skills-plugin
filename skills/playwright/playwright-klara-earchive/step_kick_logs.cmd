@echo off
REM step_kick_logs.cmd <TENANT_UUID>
REM Kicks off luz-skill-flow-logs in the background (start /b), prints output path on stdout.
setlocal EnableDelayedExpansion
set "TENANT=%~1"
if "%TENANT%"=="" (
    echo usage: step_kick_logs.cmd ^<TENANT_UUID^> 1>&2
    exit /b 2
)
set "SKILL_DIR=%~dp0"
set "SKILL_DIR=%SKILL_DIR:~0,-1%"
for %%I in ("%SKILL_DIR%\..") do set "SKILLS_ROOT=%%~fI"
set "FLOW_LOGS=%SKILLS_ROOT%\luz-skill-flow-logs\trace_flow_logs.cmd"

if not exist "%FLOW_LOGS%" (
    echo luz-skill-flow-logs runner not found at: %FLOW_LOGS% 1>&2
    exit /b 1
)

if not defined SEVERITY  set "SEVERITY=ERROR"
if not defined FRESHNESS set "FRESHNESS=10m"
if not defined LIMIT     set "LIMIT=2000"

for /f %%T in ('powershell -NoProfile -Command "[int][double]::Parse((Get-Date -UFormat %%s))"') do set "STAMP=%%T"
set "OUT=%TEMP%\earchive-flow-logs-%STAMP%.txt"

start /b "" cmd /c "set SEVERITY=%SEVERITY%& set FRESHNESS=%FRESHNESS%& set LIMIT=%LIMIT%& "%FLOW_LOGS%" %TENANT% > "%OUT%" 2>&1"
echo %OUT%
endlocal & exit /b 0
