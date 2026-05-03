@echo off
node -e "const fs=require('fs'),os=require('os'),path=require('path');const d=path.join(os.tmpdir(),'playwright-klara-earchive-'+Date.now());fs.mkdirSync(d,{recursive:true});process.stdout.write(d)"
exit /b %errorlevel%
