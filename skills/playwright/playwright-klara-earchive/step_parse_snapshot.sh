#!/usr/bin/env bash
# step_parse_snapshot.sh <snapshot.yml>
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node "$SKILL_DIR/_lib/parse_snapshot.js" "$@"
