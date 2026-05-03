#!/usr/bin/env bash
# claude-profile-switcher — manage multiple isolated Claude Code subscription profiles.
#
# Each profile = a directory under $CLAUDE_PROFILES_DIR (default ~/.claude-profiles/).
# The script sets CLAUDE_CONFIG_DIR=<that dir> so credentials, settings, and session
# state stay isolated. Two parallel terminals using different profiles can be logged
# in as different subscriptions at the same time.
#
# Linux + Windows (Git Bash / WSL). macOS NOT supported — Claude Code uses the
# Keychain there, which bypasses CLAUDE_CONFIG_DIR.

set -euo pipefail

PROFILES_DIR=${CLAUDE_PROFILES_DIR:-$HOME/.claude-profiles}

usage() {
  cat <<EOF
claude-profile-switcher — manage multiple Claude Code subscription profiles

Usage:
  $0 list                       # list profiles (current shell's profile is marked *)
  $0 add <name>                 # create the profile dir (non-interactive, idempotent)
  $0 login <name>               # launch claude under the profile so you can /login (interactive)
  $0 use <name>                 # exec a new shell with CLAUDE_CONFIG_DIR set
  $0 run <name> [args...]       # exec 'claude' directly under the profile
  $0 path <name>                # print the profile's absolute dir
  $0 current                    # print which profile the current shell uses
  $0 remove <name>              # delete the profile dir (confirm prompt)
  $0 wire                       # (re)generate claude_<name> shortcut functions for every profile

Profiles dir: $PROFILES_DIR
Override with CLAUDE_PROFILES_DIR.
EOF
}

sanitize_name() {
  printf '%s' "$1" | sed 's/[^a-zA-Z0-9]/_/g'
}

profile_dir() { printf '%s/%s' "$PROFILES_DIR" "$1"; }

require_name() {
  if [[ -z "${1:-}" ]]; then
    echo "ERROR: profile name required." >&2
    usage >&2
    exit 1
  fi
}

require_exists() {
  local name=$1 dir
  dir=$(profile_dir "$name")
  if [[ ! -d "$dir" ]]; then
    echo "ERROR: profile '$name' not found at $dir" >&2
    echo "       Create it with: $0 add $name" >&2
    exit 1
  fi
  printf '%s' "$dir"
}

cmd_list() {
  if [[ ! -d "$PROFILES_DIR" ]]; then
    echo "(no profiles yet — '$0 add <name>' to create one)"
    return 0
  fi
  local current="${CLAUDE_CONFIG_DIR:-}"
  local found=0 d name marker
  shopt -s nullglob
  for d in "$PROFILES_DIR"/*/; do
    name=$(basename "$d")
    # Skip the auto-generated bin/ directory (Windows shortcuts target).
    [[ "$name" == "bin" ]] && continue
    found=1
    marker=" "
    [[ "${d%/}" == "$current" ]] && marker="*"
    printf "%s %s\n" "$marker" "$name"
  done
  shopt -u nullglob
  (( found )) || echo "(no profiles yet — '$0 add <name>' to create one)"
}

cmd_add() {
  require_name "${1:-}"
  local name=$1
  local dir; dir=$(profile_dir "$name")
  if [[ -d "$dir" ]]; then
    echo "[claude-profile] profile '$name' already exists at $dir (no-op)"
    return 0
  fi
  mkdir -p "$dir"
  echo "[claude-profile] created $dir"
  echo
  echo "[claude-profile] wiring shortcut commands…"
  cmd_wire
  echo
  echo "Next: run this in your OWN terminal to authenticate the account —"
  echo "  $0 login $name"
}

cmd_login() {
  require_name "${1:-}"
  local name=$1
  local dir; dir=$(profile_dir "$name")
  if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir"
    echo "[claude-profile] created $dir" >&2
  fi
  echo "[claude-profile] launching 'claude' under profile '$name'..." >&2
  echo "[claude-profile] inside claude: type '/login' and complete the OAuth flow." >&2
  echo "[claude-profile] when done, exit claude (Ctrl-D or /exit) — credentials persist here." >&2
  CLAUDE_CONFIG_DIR="$dir" exec claude
}

cmd_use() {
  require_name "${1:-}"
  local dir; dir=$(require_exists "$1")
  echo "[claude-profile] entering subshell with CLAUDE_CONFIG_DIR=$dir" >&2
  echo "[claude-profile] type 'exit' to return to your previous shell." >&2
  CLAUDE_CONFIG_DIR="$dir" exec "${SHELL:-bash}"
}

cmd_run() {
  require_name "${1:-}"
  local name=$1; shift
  local dir; dir=$(require_exists "$name")
  echo "[claude-profile] running 'claude $*' under profile '$name'" >&2
  CLAUDE_CONFIG_DIR="$dir" exec claude "$@"
}

cmd_path() {
  require_name "${1:-}"
  printf '%s\n' "$(profile_dir "$1")"
}

cmd_current() {
  local cur="${CLAUDE_CONFIG_DIR:-}"
  if [[ -z "$cur" ]]; then
    echo "(no profile — CLAUDE_CONFIG_DIR is unset; using default ~/.claude)"
    return 0
  fi
  if [[ "$cur" == "$PROFILES_DIR"/* ]]; then
    local name=${cur#$PROFILES_DIR/}
    name=${name%/}
    printf '%s  (%s)\n' "$name" "$cur"
  else
    printf '(custom CLAUDE_CONFIG_DIR=%s — not under %s)\n' "$cur" "$PROFILES_DIR"
  fi
}

cmd_remove() {
  require_name "${1:-}"
  local dir; dir=$(require_exists "$1")
  read -r -p "[claude-profile] DELETE $dir and its credentials? [y/N] " ans
  case "$ans" in
    y|Y|yes|YES)
      rm -rf "$dir"
      echo "[claude-profile] removed $dir"
      echo
      echo "[claude-profile] regenerating shortcut commands…"
      cmd_wire
      ;;
    *)
      echo "[claude-profile] aborted."
      exit 1
      ;;
  esac
}

activate_rc_files() {
  # Idempotently append the source line to the user's shell rc files so the
  # generated shortcut functions are picked up by new shells.
  local marker='# claude-profile-switcher: activate per-profile shortcuts'
  local src_line='[ -f "$HOME/.claude-profiles/.shell-init.sh" ] && . "$HOME/.claude-profiles/.shell-init.sh"'
  # .bash_profile is common on Git Bash / macOS where .bashrc may not exist.
  local rc_files=("$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.bash_profile")
  local rc added=0 existing=0
  for rc in "${rc_files[@]}"; do
    [[ -f "$rc" ]] || continue
    existing=$((existing+1))
    if grep -Fq '.claude-profiles/.shell-init.sh' "$rc"; then
      printf '  already activated in: %s\n' "$rc"
    else
      printf '\n%s\n%s\n' "$marker" "$src_line" >> "$rc"
      printf '  appended activation to: %s\n' "$rc"
      added=$((added+1))
    fi
  done
  if (( existing == 0 )); then
    printf '  (no shell rc file found at %s)\n' "$HOME/.bashrc, $HOME/.zshrc, or $HOME/.bash_profile"
    printf '  → source the shortcuts manually with:\n'
    printf '      . %s/.shell-init.sh\n' "$PROFILES_DIR"
    printf '    or create ~/.bashrc with that line so it activates on every new shell.\n'
  fi
  return $added
}

cmd_wire() {
  local init_file="$PROFILES_DIR/.shell-init.sh"
  mkdir -p "$PROFILES_DIR"
  {
    printf '# claude-profile-switcher: auto-generated. Do not edit directly.\n'
    printf '# Re-run "%s wire" to regenerate.\n\n' "$0"
  } > "$init_file"

  shopt -s nullglob
  local count=0 d name fn
  for d in "$PROFILES_DIR"/*/; do
    name=$(basename "$d")
    # Skip the auto-generated bin/ directory so it doesn't masquerade as a profile.
    [[ "$name" == "bin" ]] && continue
    fn="claude_$(sanitize_name "$name")"
    printf '%s() { CLAUDE_CONFIG_DIR=%q command claude "$@"; }\n' "$fn" "${d%/}" >> "$init_file"
    count=$((count+1))
    printf '  %-40s →  %s\n' "$fn" "${d%/}"
  done
  shopt -u nullglob

  if (( count == 0 )); then
    echo "(no profiles to wire — '$0 add <name>' first)"
    return 0
  fi
  echo
  echo "Wrote $count shortcut(s) to $init_file"
  echo
  echo "Activating in shell rc files:"
  set +e
  activate_rc_files
  local rc_added=$?
  set -e
  if (( rc_added > 0 )); then
    echo
    echo "Open a NEW terminal to use the shortcuts (or 'source ~/.bashrc' here)."
  fi
  echo "Each profile has a 'claude_<name>' command that runs claude under that profile"
  echo "(args pass through, e.g. claude_work --help)."
}

mkdir -p "$PROFILES_DIR" 2>/dev/null || true

case "${1:-}" in
  list|ls)            shift; cmd_list "$@" ;;
  add|create|new)     shift; cmd_add "$@" ;;
  login|signin)       shift; cmd_login "$@" ;;
  use|switch)         shift; cmd_use "$@" ;;
  run|exec)           shift; cmd_run "$@" ;;
  path|dir)           shift; cmd_path "$@" ;;
  current|whoami)     shift; cmd_current "$@" ;;
  remove|rm|delete)   shift; cmd_remove "$@" ;;
  wire|setup-shortcuts) shift; cmd_wire "$@" ;;
  ""|-h|--help|help)  usage ;;
  *)
    echo "ERROR: unknown subcommand '$1'" >&2
    usage >&2
    exit 1
    ;;
esac
