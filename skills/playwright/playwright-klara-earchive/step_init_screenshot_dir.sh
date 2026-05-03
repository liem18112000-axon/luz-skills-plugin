#!/usr/bin/env bash
# step_init_screenshot_dir.sh
# Creates <os-tmp>/playwright-klara-earchive-<epoch-ms>/ and prints its absolute path.
# Uses node so the path is OS-native (Windows backslashes on Windows, etc.) — keeps
# absolute paths consistent across .sh-via-Git-Bash and .cmd invocations.
exec node -e "const fs=require('fs'),os=require('os'),path=require('path');const d=path.join(os.tmpdir(),'playwright-klara-earchive-'+Date.now());fs.mkdirSync(d,{recursive:true});process.stdout.write(d)"
