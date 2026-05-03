#!/usr/bin/env bash
# bootstrap.sh — verify deps for playwright-klara-earchive; install where possible.
# Idempotent: safe to call at the start of every skill invocation.
# Exit 0 = all deps present (or installed in-process). Exit 1 = manual action required.

set -u
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="$(cd "$SKILL_DIR/.." && pwd)"
MISSING=()
INSTALLED=()

log()  { printf '[bootstrap] %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

detect_pm() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    have brew && { echo brew; return; }
  elif [[ "$(uname -s)" == "Linux" ]]; then
    have apt-get && { echo apt; return; }
    have dnf     && { echo dnf; return; }
    have yum     && { echo yum; return; }
    have pacman  && { echo pacman; return; }
  fi
  echo none
}

PM="$(detect_pm)"

install_pkg() {
  local pkg="$1"
  case "$PM" in
    brew)   brew install "$pkg" ;;
    apt)    sudo apt-get update -qq && sudo apt-get install -y "$pkg" ;;
    dnf)    sudo dnf install -y "$pkg" ;;
    yum)    sudo yum install -y "$pkg" ;;
    pacman) sudo pacman -S --noconfirm "$pkg" ;;
    *)      return 1 ;;
  esac
}

check_node() {
  if have node; then return 0; fi
  log "node not found — attempting install via $PM"
  case "$PM" in
    brew|apt|dnf|yum|pacman) install_pkg nodejs && INSTALLED+=(node) && return 0 ;;
  esac
  MISSING+=("node — install from https://nodejs.org/")
  return 1
}

check_gcloud() {
  if have gcloud; then return 0; fi
  log "gcloud not found — auto-install skipped (interactive auth required)"
  MISSING+=("gcloud — install from https://cloud.google.com/sdk/docs/install, then run: gcloud auth login")
  return 1
}

check_sibling_skill() {
  local name="$1"
  if [[ -f "$SKILLS_ROOT/$name/SKILL.md" ]]; then return 0; fi
  MISSING+=("sibling skill '$name' — expected at $SKILLS_ROOT/$name/")
  return 1
}

check_node    || true
check_gcloud  || true
check_sibling_skill luz-skill-flow-logs || true

if ((${#INSTALLED[@]})); then
  log "installed during this run: ${INSTALLED[*]}"
fi

if ((${#MISSING[@]})); then
  log "MISSING dependencies — manual action required:"
  for m in "${MISSING[@]}"; do log "  - $m"; done
  log "After installing, re-invoke the skill."
  exit 1
fi

log "all deps present"
exit 0
