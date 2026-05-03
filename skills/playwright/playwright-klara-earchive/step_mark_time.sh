#!/usr/bin/env bash
# step_mark_time.sh — print current epoch milliseconds (single line, no newline noise).
node -e 'process.stdout.write(String(Date.now()))'
echo
