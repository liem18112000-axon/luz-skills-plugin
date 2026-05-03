#!/usr/bin/env bash
# bootstrap.sh — verify python + ngrok + (optional) markdown package.
# Idempotent. Exit 0 = ready; exit 1 = manual action needed.
set -u
MISSING=()
INSTALLED=()
log()  { printf '[bootstrap] %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

PY=""
if have python3; then PY=python3
elif have python; then PY=python
fi

detect_pm() {
  if [[ "$(uname -s)" == "Darwin" ]] && have brew; then echo brew
  elif have apt-get; then echo apt
  elif have dnf;     then echo dnf
  elif have pacman;  then echo pacman
  else echo none
  fi
}
PM="$(detect_pm)"

# python
if [[ -z "$PY" ]]; then
  log "python not found — attempting install via $PM"
  case "$PM" in
    brew)   brew install python && PY=python3 && INSTALLED+=(python) ;;
    apt)    sudo apt-get update -qq && sudo apt-get install -y python3 python3-pip && PY=python3 && INSTALLED+=(python) ;;
    dnf)    sudo dnf install -y python3 python3-pip && PY=python3 && INSTALLED+=(python) ;;
    pacman) sudo pacman -S --noconfirm python python-pip && PY=python3 && INSTALLED+=(python) ;;
    *)      MISSING+=("python — install from https://www.python.org/") ;;
  esac
fi

# ngrok
if ! have ngrok; then
  log "ngrok not found — attempting install via $PM"
  case "$PM" in
    brew)   brew install --cask ngrok && INSTALLED+=(ngrok) ;;
    apt)    curl -fsSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null \
            && echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | sudo tee /etc/apt/sources.list.d/ngrok.list >/dev/null \
            && sudo apt-get update -qq && sudo apt-get install -y ngrok && INSTALLED+=(ngrok) ;;
    *)      MISSING+=("ngrok — install from https://ngrok.com/download (then: ngrok config add-authtoken <YOUR-TOKEN>)") ;;
  esac
fi

# ngrok authtoken — required before any tunnel can open
if have ngrok; then
  if ! ngrok config check >/dev/null 2>&1; then
    MISSING+=("ngrok authtoken — sign up at https://dashboard.ngrok.com/get-started/your-authtoken, then run: ngrok config add-authtoken <YOUR-TOKEN>")
  fi
fi

# markdown package (optional but strongly preferred)
if [[ -n "$PY" ]]; then
  if ! "$PY" -c "import markdown" >/dev/null 2>&1; then
    log "python 'markdown' package not found — installing via pip --user"
    "$PY" -m pip install --user markdown >/dev/null 2>&1 \
      && INSTALLED+=("python-markdown") \
      || log "could not install markdown — server will fall back to <pre> for .md files (still works)"
  fi
fi

if ((${#INSTALLED[@]})); then
  log "installed: ${INSTALLED[*]}"
fi
if ((${#MISSING[@]})); then
  log "MISSING — manual action required:"
  for m in "${MISSING[@]}"; do log "  - $m"; done
  exit 1
fi
log "ready"
exit 0
