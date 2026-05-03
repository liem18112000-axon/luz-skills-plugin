@echo off
REM step_mark_time.cmd - print current epoch milliseconds.
node -e "process.stdout.write(String(Date.now()))"
echo.
