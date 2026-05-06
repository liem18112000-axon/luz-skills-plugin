#!/usr/bin/env bash
# earchive-data-prepare — find primary across rs-{0,1,2}, then truncate + regenerate.

set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SKILL_DIR/_lib"

PORT="${PORT:-27017}"
NAMESPACE="${NAMESPACE:-dev-mongodb-clusters}"
STS_NAME="${STS_NAME:-luz-mongodb02-cluster-rs}"

PF_PID=""
PRIMARY=""

cleanup() {
    if [ -n "$PF_PID" ] && kill -0 "$PF_PID" 2>/dev/null; then
        kill "$PF_PID" 2>/dev/null || true
        wait "$PF_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

# 1. Bootstrap deps.
bash "$SKILL_DIR/bootstrap.sh" || exit 1

# 2. Resolve params and print the tuple (mask nothing — none of these are secrets).
TENANT_ID="${TENANT_ID:-a5e06d74-137c-4a9e-9adc-9eccdccc2d17}"
DOC_COUNT="${DOC_COUNT:-128000}"
FOLDER_COUNT="${FOLDER_COUNT:-30}"
MAX_NESTED="${MAX_NESTED:-3}"
MAX_FOLDERS_PER_DOC="${MAX_FOLDERS_PER_DOC:-10}"
BATCH_SIZE="${BATCH_SIZE:-1000}"
MATERIALIZE="${MATERIALIZE:-true}"
RESTRICTED_FOLDER_PCT="${RESTRICTED_FOLDER_PCT:-75}"
CONFIRM="${CONFIRM:-}"

echo "[prepare] tenant            = $TENANT_ID"
echo "[prepare] doc count         = $DOC_COUNT"
echo "[prepare] folder count      = $FOLDER_COUNT"
echo "[prepare] max nested        = $MAX_NESTED"
echo "[prepare] max folders/doc   = $MAX_FOLDERS_PER_DOC"
echo "[prepare] batch size        = $BATCH_SIZE"
echo "[prepare] materialize       = $MATERIALIZE"
echo "[prepare] restricted pct    = $RESTRICTED_FOLDER_PCT"
echo "[prepare] namespace         = $NAMESPACE"
echo "[prepare] sts base          = $STS_NAME"
echo "[prepare] confirm truncate  = ${CONFIRM:-(unset — will refuse)}"

export TENANT_ID DOC_COUNT FOLDER_COUNT MAX_NESTED MAX_FOLDERS_PER_DOC BATCH_SIZE MATERIALIZE RESTRICTED_FOLDER_PCT PORT CONFIRM

start_pf() {
    local pod="$1"
    echo "[prepare] port-forward → $pod"
    kubectl port-forward "$pod" "${PORT}:${PORT}" -n "$NAMESPACE" >/dev/null 2>&1 &
    PF_PID=$!
    # Wait up to 10 s for local port to accept TCP.
    local i=0
    while [ "$i" -lt 20 ]; do
        if (echo > /dev/tcp/localhost/${PORT}) 2>/dev/null; then
            return 0
        fi
        sleep 0.5
        i=$((i + 1))
    done
    echo "[prepare] port-forward to $pod did not become ready in 10s" >&2
    return 1
}

stop_pf() {
    if [ -n "$PF_PID" ] && kill -0 "$PF_PID" 2>/dev/null; then
        kill "$PF_PID" 2>/dev/null || true
        wait "$PF_PID" 2>/dev/null || true
    fi
    PF_PID=""
}

# 3. Loop replicas, probe, find primary.
for idx in 0 1 2; do
    pod="${STS_NAME}-${idx}"
    if ! start_pf "$pod"; then
        stop_pf
        continue
    fi
    MODE=probe node "$LIB_DIR/prepare_data.js"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        PRIMARY="$pod"
        echo "[prepare] primary = $PRIMARY (rs-${idx})"
        break
    elif [ "$rc" -eq 2 ]; then
        echo "[prepare] $pod is not primary, trying next"
        stop_pf
        continue
    else
        echo "[prepare] probe error against $pod (rc=$rc)" >&2
        stop_pf
        exit 1
    fi
done

if [ -z "$PRIMARY" ]; then
    echo "[prepare] no primary found across ${STS_NAME}-{0,1,2}" >&2
    exit 1
fi

# 4. Run the actual generator (port-forward to PRIMARY still active).
node "$LIB_DIR/prepare_data.js"
rc=$?

if [ "$rc" -ne 0 ]; then
    echo "[prepare] generator exited with $rc" >&2
    exit "$rc"
fi

echo "[prepare] done."
