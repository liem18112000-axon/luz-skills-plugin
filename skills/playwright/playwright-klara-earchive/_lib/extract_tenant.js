#!/usr/bin/env node
// extract_tenant.js [path]
// Reads a DOM dump (or stdin if no path) and prints the first UUID found.
// Usage:
//   extract_tenant.js dom.txt
//   echo "...html..." | extract_tenant.js

const fs = require('fs');

function findUuid(text) {
  const m = text.match(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/);
  return m ? m[0] : null;
}

const path = process.argv[2];
if (path) {
  const uuid = findUuid(fs.readFileSync(path, 'utf8'));
  if (!uuid) { console.error('no UUID found'); process.exit(1); }
  process.stdout.write(uuid + '\n');
} else {
  let buf = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', d => buf += d);
  process.stdin.on('end', () => {
    const uuid = findUuid(buf);
    if (!uuid) { console.error('no UUID found'); process.exit(1); }
    process.stdout.write(uuid + '\n');
  });
}
