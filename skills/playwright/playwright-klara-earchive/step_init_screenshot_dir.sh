#!/usr/bin/env bash
# step_init_screenshot_dir.sh
# Creates <cwd>/.playwright-mcp/screenshots-<epoch-ms>/ and prints its absolute path.
#
# Why under .playwright-mcp and not os.tmpdir(): the Playwright MCP server restricts
# file writes to a small set of allowed roots (the project dir and its .playwright-mcp/
# subfolder). Screenshots written outside those roots fail with
#   "File access denied: <path> is outside allowed roots."
# Minting the dir under .playwright-mcp guarantees browser_take_screenshot can write
# to it.
exec node -e "const fs=require('fs'),path=require('path');const root=path.join(process.cwd(),'.playwright-mcp');fs.mkdirSync(root,{recursive:true});const d=path.join(root,'screenshots-'+Date.now());fs.mkdirSync(d,{recursive:true});process.stdout.write(d)"
