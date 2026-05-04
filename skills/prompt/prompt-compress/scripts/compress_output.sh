#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -x "$DIR/.venv/Scripts/python.exe" ]; then
    PY="$DIR/.venv/Scripts/python.exe"
elif [ -x "$DIR/.venv/bin/python" ]; then
    PY="$DIR/.venv/bin/python"
else
    echo "venv not found at $DIR/.venv — run: bash $DIR/install.sh" >&2
    exit 3
fi

exec "$PY" "$DIR/scripts/compress_output.py" "$@"
