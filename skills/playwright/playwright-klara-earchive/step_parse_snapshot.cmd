@echo off
REM step_parse_snapshot.cmd <snapshot.yml>
node "%~dp0_lib\parse_snapshot.js" %*
exit /b %errorlevel%
