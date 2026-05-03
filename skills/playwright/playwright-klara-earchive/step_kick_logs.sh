#!/usr/bin/env bash
# step_kick_logs.sh <TENANT_UUID>
# Kicks off luz-skill-flow-logs in the background, scoped tight (FRESHNESS=10m).
# Output is redirected to a known temp path; prints that path on stdout so the
# caller knows where to read it later (Step 7 / drain).
set -u
TENANT="${1:-}"
if [[ -z "$TENANT" ]]; then echo 'usage: step_kick_logs.sh <TENANT_UUID>' >&2; exit 2; fi

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="$(cd "$SKILL_DIR/.." && pwd)"
FLOW_LOGS="$SKILLS_ROOT/luz-skill-flow-logs/trace_flow_logs.sh"

if [[ ! -x "$FLOW_LOGS" ]]; then
  echo "luz-skill-flow-logs runner not found / not executable at: $FLOW_LOGS" >&2
  exit 1
fi

OUT="${TMPDIR:-/tmp}/earchive-flow-logs-$(date +%s).txt"
SEVERITY="${SEVERITY:-ERROR}" FRESHNESS="${FRESHNESS:-10m}" LIMIT="${LIMIT:-2000}" \
  nohup "$FLOW_LOGS" "$TENANT" > "$OUT" 2>&1 &

echo "$OUT"
