#!/usr/bin/env node
// summarize_logs.js <log-file>
// Counts known anomaly patterns in a luz-skill-flow-logs output file.
// Output: JSON to stdout.

const fs = require('fs');

const path = process.argv[2];
if (!path) {
  console.error('usage: summarize_logs.js <log-file>');
  process.exit(2);
}

let text;
try {
  text = fs.readFileSync(path, 'utf8');
} catch (e) {
  console.error('cannot read ' + path + ': ' + e.message);
  process.exit(1);
}

const count = re => (text.match(re) || []).length;
const distinctTargets = re => {
  const set = new Set();
  let m; const g = new RegExp(re.source, 'g');
  while ((m = g.exec(text)) !== null) set.add(m[1]);
  return [...set];
};

const out = {
  totalSize:                          text.length,
  mongoSocketReadException:           count(/MongoSocketReadException/g),
  mongoQueryExceededMemoryLimit:      count(/QueryExceededMemoryLimitNoDiskUseAllowed/g),
  fiveHundredErrors:                  count(/Cannot execute \[500/g),
  archivesDirectoriesBranded500:      count(/\[500[^\]]*\][^\n]*\/archives\/directories\/branded/g),
  distinct500Targets:                 distinctTargets(/target-uri \[(http:[^\]]+)\]/),
};
process.stdout.write(JSON.stringify(out, null, 2) + '\n');
