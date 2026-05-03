@echo off
node "%~dp0_lib\extract_tenant.js" %*
exit /b %errorlevel%
