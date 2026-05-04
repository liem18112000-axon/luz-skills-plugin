#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="$DIR/models"

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

echo "==> downloading models to $MODELS_DIR"
mkdir -p "$MODELS_DIR"
MODELS_DIR_ESCAPED="$MODELS_DIR" PYTHONIOENCODING=utf-8 "$VENV_PY" - <<'PY'
import os, sys
from huggingface_hub import snapshot_download

base = os.environ["MODELS_DIR_ESCAPED"]
targets = [
    ("Helsinki-NLP/opus-mt-en-zh", "opus-mt-en-zh"),
    ("raynardj/wenyanwen-chinese-translate-to-ancient",
     "wenyanwen-chinese-translate-to-ancient"),
    ("Helsinki-NLP/opus-mt-zh-en", "opus-mt-zh-en"),
    ("raynardj/wenyanwen-ancient-translate-to-modern",
     "wenyanwen-ancient-translate-to-modern"),
]
for repo, name in targets:
    dest = os.path.join(base, name)
    if os.path.exists(os.path.join(dest, "config.json")):
        print(f"  ok  {name} (cached)", flush=True)
        continue
    print(f"  >>  {repo}", flush=True)
    snapshot_download(repo, local_dir=dest)
    print(f"  ok  {name}", flush=True)
PY

echo
echo "==> models present:"
du -sh "$MODELS_DIR"/* 2>/dev/null || true

echo
echo "==> done. Try: /prompt-compress <some-file.md>"
