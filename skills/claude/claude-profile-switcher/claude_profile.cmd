@echo off
setlocal enabledelayedexpansion

REM claude-profile-switcher - Windows runner.
REM
REM Each profile = a directory under %CLAUDE_PROFILES_DIR% (default %USERPROFILE%\.claude-profiles).
REM The script sets CLAUDE_CONFIG_DIR=<that dir> so credentials, settings, and session
REM state stay isolated. Two parallel terminals using different profiles can be logged
REM in as different subscriptions at the same time.
REM
REM Linux + Windows. macOS NOT supported (Claude Code uses the Keychain there).

if not defined CLAUDE_PROFILES_DIR set "CLAUDE_PROFILES_DIR=%USERPROFILE%\.claude-profiles"

if "%~1"=="" goto :usage
if /i "%~1"=="-h" goto :usage
if /i "%~1"=="--help" goto :usage
if /i "%~1"=="help" goto :usage
if /i "%~1"=="list" goto :do_list
if /i "%~1"=="ls" goto :do_list
if /i "%~1"=="add" goto :do_add
if /i "%~1"=="create" goto :do_add
if /i "%~1"=="new" goto :do_add
if /i "%~1"=="login" goto :do_login
if /i "%~1"=="signin" goto :do_login
if /i "%~1"=="use" goto :do_use
if /i "%~1"=="switch" goto :do_use
if /i "%~1"=="run" goto :do_run
if /i "%~1"=="exec" goto :do_run
if /i "%~1"=="path" goto :do_path
if /i "%~1"=="dir" goto :do_path
if /i "%~1"=="current" goto :do_current
if /i "%~1"=="whoami" goto :do_current
if /i "%~1"=="remove" goto :do_remove
if /i "%~1"=="rm" goto :do_remove
if /i "%~1"=="delete" goto :do_remove
if /i "%~1"=="wire" goto :do_wire
if /i "%~1"=="setup-shortcuts" goto :do_wire

1>&2 echo ERROR: unknown subcommand '%~1'
goto :usage_err

:usage
echo claude-profile-switcher - manage multiple Claude Code subscription profiles
echo.
echo Usage:
echo   %~n0 list                       List profiles ^(current shell's profile is marked *^)
echo   %~n0 add ^<name^>                 Create the profile dir ^(non-interactive, idempotent^)
echo   %~n0 login ^<name^>               Launch claude under the profile so you can /login ^(interactive^)
echo   %~n0 use ^<name^>                 Open a subshell with CLAUDE_CONFIG_DIR set
echo   %~n0 run ^<name^> [args...]       Exec 'claude' under the profile
echo   %~n0 path ^<name^>                Print the profile's absolute dir
echo   %~n0 current                    Print which profile the current shell uses
echo   %~n0 remove ^<name^>              Delete the profile dir ^(confirm prompt^)
echo   %~n0 wire                       ^(re^)generate claude_^<name^> shortcut .cmd files for every profile
echo.
echo Profiles dir: %CLAUDE_PROFILES_DIR%
echo Override with CLAUDE_PROFILES_DIR.
exit /b 0

:usage_err
1>&2 echo Run "%~n0 --help" for usage.
exit /b 1

:do_list
if not exist "%CLAUDE_PROFILES_DIR%" (
    echo (no profiles yet - "%~n0 add ^<name^>" to create one^)
    exit /b 0
)
set "_FOUND=0"
for /d %%D in ("%CLAUDE_PROFILES_DIR%\*") do (
    set "_NAME=%%~nxD"
    if /i not "!_NAME!"=="bin" (
        set "_FOUND=1"
        set "_MARK= "
        if /i "%%~fD"=="%CLAUDE_CONFIG_DIR%" set "_MARK=*"
        echo !_MARK! !_NAME!
    )
)
if "!_FOUND!"=="0" echo (no profiles yet - "%~n0 add ^<name^>" to create one^)
exit /b 0

:do_add
if "%~2"=="" (
    1>&2 echo ERROR: profile name required.
    goto :usage_err
)
set "_NAME=%~2"
set "_DIR=%CLAUDE_PROFILES_DIR%\!_NAME!"
if exist "!_DIR!" (
    echo [claude-profile] profile '!_NAME!' already exists at !_DIR! ^(no-op^)
    exit /b 0
)
mkdir "!_DIR!" 2>nul
echo [claude-profile] created !_DIR!
call :wire_silent
set "_SAN=!_NAME:-=_!"
set "_SAN=!_SAN:.=_!"
set "_SAN=!_SAN: =_!"
echo [claude-profile] shortcut 'claude_!_SAN!' wired ^(run '%~n0 wire' to see how to activate it^)
echo.
echo Next: run this in your OWN terminal to authenticate the account -
echo   %~n0 login !_NAME!
exit /b 0

:do_login
if "%~2"=="" (
    1>&2 echo ERROR: profile name required.
    goto :usage_err
)
set "_NAME=%~2"
set "_DIR=%CLAUDE_PROFILES_DIR%\!_NAME!"
if not exist "!_DIR!" (
    mkdir "!_DIR!" 2>nul
    1>&2 echo [claude-profile] created !_DIR!
)
1>&2 echo [claude-profile] launching 'claude' under profile '!_NAME!'...
1>&2 echo [claude-profile] inside claude: type '/login' and complete the OAuth flow.
1>&2 echo [claude-profile] when done, exit claude (Ctrl-D or /exit) - credentials persist here.
set "CLAUDE_CONFIG_DIR=!_DIR!"
claude
exit /b %errorlevel%

:do_use
if "%~2"=="" (
    1>&2 echo ERROR: profile name required.
    goto :usage_err
)
set "_NAME=%~2"
set "_DIR=%CLAUDE_PROFILES_DIR%\!_NAME!"
if not exist "!_DIR!" (
    1>&2 echo ERROR: profile '!_NAME!' not found at !_DIR!
    1>&2 echo        Create it with: %~n0 add !_NAME!
    exit /b 1
)
1>&2 echo [claude-profile] entering subshell with CLAUDE_CONFIG_DIR=!_DIR!
1>&2 echo [claude-profile] type 'exit' to return to your previous shell.
set "CLAUDE_CONFIG_DIR=!_DIR!"
cmd /k
exit /b %errorlevel%

:do_run
if "%~2"=="" (
    1>&2 echo ERROR: profile name required.
    goto :usage_err
)
set "_NAME=%~2"
set "_DIR=%CLAUDE_PROFILES_DIR%\!_NAME!"
if not exist "!_DIR!" (
    1>&2 echo ERROR: profile '!_NAME!' not found at !_DIR!
    exit /b 1
)
shift
shift
set "_ARGS="
:run_collect
if "%~1"=="" goto :run_exec
if defined _ARGS (
    set "_ARGS=!_ARGS! %1"
) else (
    set "_ARGS=%1"
)
shift
goto :run_collect
:run_exec
1>&2 echo [claude-profile] running 'claude !_ARGS!' under profile '!_NAME!'
set "CLAUDE_CONFIG_DIR=!_DIR!"
claude !_ARGS!
exit /b %errorlevel%

:do_path
if "%~2"=="" (
    1>&2 echo ERROR: profile name required.
    goto :usage_err
)
echo %CLAUDE_PROFILES_DIR%\%~2
exit /b 0

:do_current
if "%CLAUDE_CONFIG_DIR%"=="" (
    echo (no profile - CLAUDE_CONFIG_DIR is unset; using default %USERPROFILE%\.claude^)
    exit /b 0
)
echo CLAUDE_CONFIG_DIR=%CLAUDE_CONFIG_DIR%
exit /b 0

:do_remove
if "%~2"=="" (
    1>&2 echo ERROR: profile name required.
    goto :usage_err
)
set "_NAME=%~2"
set "_DIR=%CLAUDE_PROFILES_DIR%\!_NAME!"
if not exist "!_DIR!" (
    1>&2 echo ERROR: profile '!_NAME!' not found at !_DIR!
    exit /b 1
)
set "_ANS="
set /p "_ANS=[claude-profile] DELETE !_DIR! and its credentials? [y/N] "
if /i "!_ANS!"=="y"   goto :remove_yes
if /i "!_ANS!"=="yes" goto :remove_yes
echo [claude-profile] aborted.
exit /b 1

:remove_yes
rmdir /s /q "!_DIR!"
echo [claude-profile] removed !_DIR!
call :wire_silent
exit /b 0

:do_wire
set "_BIN=%CLAUDE_PROFILES_DIR%\bin"
if not exist "%_BIN%" mkdir "%_BIN%" 2>nul
REM clear stale shortcuts
for %%F in ("%_BIN%\claude_*.cmd") do del /q "%%F" 2>nul

set "_COUNT=0"
for /d %%D in ("%CLAUDE_PROFILES_DIR%\*") do (
    set "_PNAME=%%~nxD"
    set "_PDIR=%%~fD"
    if /i not "!_PNAME!"=="bin" (
        set "_SAN=!_PNAME:-=_!"
        set "_SAN=!_SAN:.=_!"
        set "_SAN=!_SAN: =_!"
        set "_OUT=%_BIN%\claude_!_SAN!.cmd"
        > "!_OUT!" echo @echo off
        >> "!_OUT!" echo set "CLAUDE_CONFIG_DIR=!_PDIR!"
        >> "!_OUT!" echo claude %%*
        set /a _COUNT+=1
        echo   claude_!_SAN!  -^>  !_PDIR!
    )
)

if "!_COUNT!"=="0" (
    echo (no profiles to wire - "%~n0 add ^<name^>" first^)
    exit /b 0
)
echo.
echo Wrote !_COUNT! shortcut(s^) to %_BIN%
echo.
echo Activating in User PATH:
call :activate_user_path "%_BIN%"
echo Each profile has a 'claude_^<name^>' command that runs claude under that profile
echo (args pass through, e.g. claude_work --help^).
exit /b 0

:wire_silent
REM Auto-wire helper used by add/remove. Regenerates shortcuts AND ensures activation.
set "_BIN=%CLAUDE_PROFILES_DIR%\bin"
if not exist "%_BIN%" mkdir "%_BIN%" 2>nul
for %%F in ("%_BIN%\claude_*.cmd") do del /q "%%F" 2>nul
for /d %%D in ("%CLAUDE_PROFILES_DIR%\*") do (
    set "_PNAME=%%~nxD"
    set "_PDIR=%%~fD"
    if /i not "!_PNAME!"=="bin" (
        set "_SAN=!_PNAME:-=_!"
        set "_SAN=!_SAN:.=_!"
        set "_SAN=!_SAN: =_!"
        set "_OUT=%_BIN%\claude_!_SAN!.cmd"
        > "!_OUT!" echo @echo off
        >> "!_OUT!" echo set "CLAUDE_CONFIG_DIR=!_PDIR!"
        >> "!_OUT!" echo claude %%*
    )
)
call :activate_user_path "%_BIN%"
exit /b 0

:activate_user_path
REM Idempotently append %~1 to the User Path environment variable via the registry
REM (using PowerShell's [Environment] API — no setx truncation).
set "_TARGET=%~1"
for /f "delims=" %%P in ('powershell -NoProfile -Command "$bin='%_TARGET%'; $p=[Environment]::GetEnvironmentVariable('Path','User'); if (-not $p) { $p='' }; if (($p -split ';' | Where-Object { $_ }) -contains $bin) { 'already-present' } else { [Environment]::SetEnvironmentVariable('Path', (($p.TrimEnd(';') + ';' + $bin).TrimStart(';')), 'User'); 'added' }"') do set "_PATH_RESULT=%%P"
if /i "!_PATH_RESULT!"=="added" (
    echo   appended to User PATH: %_TARGET%
    echo.
    echo Open a NEW terminal to use the shortcuts ^(the current terminal won't see the PATH change^).
) else (
    echo   already in User PATH: %_TARGET%
)
exit /b 0
