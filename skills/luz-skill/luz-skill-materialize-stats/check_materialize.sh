#!/usr/bin/env bash
# Count documents by materialise state for a Luz tenant.
#
# Port-forwards the dev MongoDB pod (luz-mongodb02-cluster-rs-0) so the
# bundled JS can connect to mongodb://localhost:27017 with the tenant
# credentials, then runs the JS and prints a per-state breakdown.
#
# Required:
#   TENANT_ID   1st positional or env  (e.g. a5e06d74-137c-4a9e-9adc-9eccdccc2d17)
#
# Optional:
#   MONGO_NAMESPACE   default 'dev-mongodb-clusters'
#   MONGO_POD         default 'luz-mongodb02-cluster-rs-0'
#   LOCAL_PORT        default '27017'  (must be free; the JS uri hard-codes 27017
#                                       unless you also set MONGO_PORT)
#   MONGO_PORT        default same as LOCAL_PORT
#   SAMPLE_LIMIT      default '10'   (sample of restricted-with-codes docs)
#   LUZ_DOCS_REPO     default '$HOME/Kepler/luz_docs' (used to find node_modules/mongodb)
#   KEEP_PORT_FORWARD default unset → tear down on exit; set '1' to leave it running

set -euo pipefail

if [[ $# -ge 1 && -n "$1" ]]; then TENANT_ID=$1; fi

if [[ -z "${TENANT_ID:-}" ]]; then
  echo "ERROR: TENANT_ID is required." >&2
  echo "  Usage: $0 <TENANT_ID>" >&2
  exit 1
fi

MONGO_NAMESPACE=${MONGO_NAMESPACE:-dev-mongodb-clusters}
MONGO_POD=${MONGO_POD:-luz-mongodb02-cluster-rs-0}
LOCAL_PORT=${LOCAL_PORT:-27017}
MONGO_PORT=${MONGO_PORT:-$LOCAL_PORT}
SAMPLE_LIMIT=${SAMPLE_LIMIT:-10}

# Best-effort default for the repo location (where node_modules/mongodb lives).
LUZ_DOCS_REPO=${LUZ_DOCS_REPO:-$HOME/Kepler/luz_docs}

is_port_open() {
  (exec 3<>"/dev/tcp/$1/$2") >/dev/null 2>&1 && exec 3<&- 3>&-
}

PF_PID=""
ensure_port_forward() {
  if is_port_open localhost "$LOCAL_PORT"; then
    echo "[mat-stats] localhost:$LOCAL_PORT already reachable — reusing." >&2
    return 0
  fi
  echo "[mat-stats] launching: kubectl port-forward $MONGO_POD ${LOCAL_PORT}:27017 -n $MONGO_NAMESPACE" >&2
  local logfile="/tmp/luz-mongo-pf-${LOCAL_PORT}.log"
  : >"$logfile" 2>/dev/null || true
  nohup kubectl port-forward "$MONGO_POD" "${LOCAL_PORT}:27017" -n "$MONGO_NAMESPACE" \
    >"$logfile" 2>&1 &
  PF_PID=$!
  disown 2>/dev/null || true

  local i
  for i in 1 2 3 4 5 6 7 8; do
    sleep 1
    if is_port_open localhost "$LOCAL_PORT"; then
      echo "[mat-stats] port-forward ready (pid=$PF_PID log=$logfile)" >&2
      return 0
    fi
    if ! kill -0 "$PF_PID" 2>/dev/null; then break; fi
  done
  echo "[mat-stats] ERROR: port-forward to $MONGO_POD failed — see $logfile" >&2
  cat "$logfile" >&2 || true
  return 1
}

cleanup() {
  if [[ -n "$PF_PID" && "${KEEP_PORT_FORWARD:-}" != "1" ]]; then
    echo "[mat-stats] tearing down port-forward pid=$PF_PID" >&2
    kill "$PF_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

ensure_port_forward

# Find node_modules/mongodb. Prefer $LUZ_DOCS_REPO/data; fall back to repo root.
NODE_PATH_DIR=""
for candidate in "$LUZ_DOCS_REPO/data/node_modules" "$LUZ_DOCS_REPO/node_modules"; do
  if [[ -d "$candidate/mongodb" ]]; then
    NODE_PATH_DIR=$candidate
    break
  fi
done

if [[ -z "$NODE_PATH_DIR" ]]; then
  echo "[mat-stats] ERROR: cannot find node_modules/mongodb." >&2
  echo "  Looked in: $LUZ_DOCS_REPO/data/node_modules, $LUZ_DOCS_REPO/node_modules" >&2
  echo "  Set LUZ_DOCS_REPO to your luz_docs checkout, or run 'npm install mongodb' there." >&2
  exit 3
fi

echo "[mat-stats] tenant=$TENANT_ID port=$LOCAL_PORT node_modules=$NODE_PATH_DIR" >&2
echo

NODE_PATH="$NODE_PATH_DIR" \
TENANT_ID="$TENANT_ID" \
MONGO_PORT="$MONGO_PORT" \
SAMPLE_LIMIT="$SAMPLE_LIMIT" \
node "$(dirname "$0")/check_materialize.js"
