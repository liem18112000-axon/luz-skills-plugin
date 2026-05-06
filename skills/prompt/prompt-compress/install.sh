#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> prompt-compress install"
echo "    target: $DIR"
echo

PYTHON_BIN="${PYTHON_BIN:-python3}"
if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
    PYTHON_BIN="python"
fi
if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
    echo "ERROR: no python3 / python on PATH" >&2
    exit 1
fi
echo "==> using $($PYTHON_BIN --version)"

if [ ! -d "$DIR/.venv" ]; then
    echo "==> creating venv at $DIR/.venv"
    "$PYTHON_BIN" -m venv "$DIR/.venv"
fi

if [ -x "$DIR/.venv/Scripts/python.exe" ]; then
    VENV_PY="$DIR/.venv/Scripts/python.exe"
elif [ -x "$DIR/.venv/bin/python" ]; then
    VENV_PY="$DIR/.venv/bin/python"
else
    echo "ERROR: venv was created but no python binary found in it" >&2
    exit 1
fi

echo "==> installing python deps"
"$VENV_PY" -m pip install --quiet --upgrade pip
"$VENV_PY" -m pip install --quiet -r "$DIR/requirements.txt"

echo "==> installing spaCy English model (en_core_web_sm, ~13 MB)"
"$VENV_PY" -m spacy download en_core_web_sm 2>&1 | tail -2

echo
echo "==> done. Try: /prompt-compress <some-file.md>"
echo
echo "    Note: any old ~/.claude/skills/prompt-compress/models/ directory and"
echo "    leftover torch packages in .venv from prior versions are no longer used"
echo "    and can be deleted to reclaim disk space."
