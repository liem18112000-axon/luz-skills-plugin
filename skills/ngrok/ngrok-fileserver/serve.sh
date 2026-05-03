#!/usr/bin/env bash
# serve.sh <FOLDER>
# Starts the python file server + ngrok tunnel. Foreground; Ctrl-C stops both.
# Env:
#   PORT=8765        local port
#   LOCAL_ONLY=1     skip ngrok, only print http://localhost:<PORT>/
#   NGROK_REGION=eu  optional ngrok region (us, eu, ap, au, sa, jp, in)
set -u
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_PY="$SKILL_DIR/_lib/server.py"
DIR="${1:-}"
if [[ -z "$DIR" ]]; then echo 'usage: serve.sh <FOLDER>' >&2; exit 2; fi
DIR="$(cd "$DIR" 2>/dev/null && pwd || true)"
if [[ -z "$DIR" || ! -d "$DIR" ]]; then echo "not a directory: $1" >&2; exit 2; fi

PORT="${PORT:-8765}"
PY=""
if   command -v python3 >/dev/null 2>&1; then PY=python3
elif command -v python  >/dev/null 2>&1; then PY=python
else echo "python not found — run bootstrap.sh first" >&2; exit 1
fi

echo "[serve] folder : $DIR" >&2
echo "[serve] port   : $PORT" >&2

# Start python server in background; trap on exit so it dies with the script
"$PY" "$SERVER_PY" "$DIR" &
SERVER_PID=$!
cleanup() {
  trap - INT TERM EXIT
  kill "$SERVER_PID" 2>/dev/null || true
  pkill -P $$ 2>/dev/null || true
}
trap cleanup INT TERM EXIT

# Brief wait so the server binds before ngrok dials in
sleep 1

if [[ "${LOCAL_ONLY:-}" == "1" ]]; then
  echo "[serve] LOCAL_ONLY=1 — public tunnel skipped"
  echo "[serve] open http://localhost:$PORT/ in your browser"
  wait "$SERVER_PID"
  exit 0
fi

if ! command -v ngrok >/dev/null 2>&1; then
  echo "[serve] ngrok not found — run bootstrap.sh, or set LOCAL_ONLY=1" >&2
  exit 1
fi

echo "[serve] PUBLIC URL is anyone-with-link readable — don't share sensitive data"
NGROK_ARGS=(http "$PORT" --log=stdout)
if [[ -n "${NGROK_REGION:-}" ]]; then NGROK_ARGS+=(--region="$NGROK_REGION"); fi

# ngrok writes its public URL to its own log; we tee + grep so user sees it loudly.
ngrok "${NGROK_ARGS[@]}" 2>&1 | awk '
  /url=https:\/\/[^[:space:]]+\.ngrok/ {
    match($0, /url=https:\/\/[^[:space:]]+\.ngrok[^[:space:]]*/);
    u=substr($0, RSTART+4, RLENGTH-4);
    if (u != last) { print "\n[serve] ╔══ PUBLIC URL ══════════════════════════════════"; print "[serve] ║ " u; print "[serve] ╚════════════════════════════════════════════════\n"; fflush(); last=u }
  }
  { print }
'
