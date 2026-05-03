@echo off
node "%~dp0_lib\summarize_logs.js" %*
exit /b %errorlevel%
