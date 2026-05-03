#!/usr/bin/env bash
# Commit (already-staged changes) → push → trigger Cloud Build → poll until
# done → rollout the latest StatefulSet image. One command shipping the
# current Luz feature branch end-to-end.
#
# The skill DOES NOT run `git add` for you — that prevents accidentally
# sweeping up dirty unrelated files (e.g. local .gitignore tweaks). Stage
# the files you want, then call this with a commit message.
#
# All steps are skipped automatically when there's nothing to do — running
# the skill on a clean tree just builds + rolls out whatever's already on
# origin. That makes it safe to re-run after a manual squash + force-push.
#
# Required (only when there are staged changes to commit):
#   MESSAGE       1st positional or env  — commit message (no AI / co-author trailer)
#
# Optional:
#   FORCE_PUSH        '1' → push with --force-with-lease (after squash / amend)
#   TRIGGER_NAME      default 'luz-docs'
#   STATEFULSET       default 'luz-docs'
#   BRANCH            default current git branch
#   BUILD_PROJECT     default 'klara-infra'
#   REGION            default 'europe-west6'
#   SKIP_BUILD        '1' → stop after push
#   SKIP_ROLLOUT      '1' → run trigger but skip the rollout step
#   TRIGGER_RETRY_SECONDS  default 30 — gap between trigger retries on FAILED_PRECONDITION
#   TRIGGER_MAX_RETRIES    default 6  — give up if this many trigger attempts fail

set -euo pipefail

if [[ $# -ge 1 && -n "$1" ]]; then MESSAGE=$1; fi

TRIGGER_NAME=${TRIGGER_NAME:-luz-docs}
STATEFULSET=${STATEFULSET:-luz-docs}
BUILD_PROJECT=${BUILD_PROJECT:-klara-infra}
REGION=${REGION:-europe-west6}
TRIGGER_RETRY_SECONDS=${TRIGGER_RETRY_SECONDS:-30}
TRIGGER_MAX_RETRIES=${TRIGGER_MAX_RETRIES:-6}

# Discover branch from git if not pinned.
if [[ -z "${BRANCH:-}" ]]; then
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
fi
if [[ -z "$BRANCH" || "$BRANCH" == "HEAD" ]]; then
  echo "ERROR: cannot determine branch (detached HEAD or not in a git repo)." >&2
  echo "  Set BRANCH=<name> explicitly." >&2
  exit 2
fi

# ─── 1) Detect what's actually needed ────────────────────────────────────
HAS_STAGED=0
if ! git diff --cached --quiet 2>/dev/null; then HAS_STAGED=1; fi

# Compare HEAD vs upstream once, decide push semantics.
NEEDS_PUSH=0
LOCAL_HASH=$(git rev-parse HEAD)
REMOTE_HASH=$(git rev-parse "origin/$BRANCH" 2>/dev/null || echo "")
if [[ "$LOCAL_HASH" != "$REMOTE_HASH" ]]; then NEEDS_PUSH=1; fi

if (( HAS_STAGED == 0 && NEEDS_PUSH == 0 )); then
  echo "[ship] working tree clean and origin/$BRANCH already at $LOCAL_HASH — skipping commit + push."
elif (( HAS_STAGED == 0 )); then
  echo "[ship] nothing staged but local is ahead of origin — skipping commit, will push existing commits."
fi

if (( HAS_STAGED == 1 )) && [[ -z "${MESSAGE:-}" ]]; then
  echo "ERROR: staged changes present but MESSAGE is empty (commit message required)." >&2
  echo "  Usage: $0 \"[LUZ-152936] <what changed>\"" >&2
  exit 1
fi

echo "[ship] branch=$BRANCH trigger=$TRIGGER_NAME statefulset=$STATEFULSET"
if (( HAS_STAGED == 1 )); then
  echo "[ship] staged files:"
  git diff --cached --name-only | sed 's/^/  /'
fi
echo

# ─── 2) Commit (only if there are staged changes; no AI trailer) ─────────
COMMIT_SHA="$LOCAL_HASH"
if (( HAS_STAGED == 1 )); then
  git commit -m "$MESSAGE"
  COMMIT_SHA=$(git rev-parse HEAD)
  NEEDS_PUSH=1   # new commit always needs to be pushed
  echo "[ship] committed $COMMIT_SHA"
fi

# ─── 3) Push (only if local diverges from origin) ────────────────────────
if (( NEEDS_PUSH == 1 )); then
  if [[ "${FORCE_PUSH:-}" == "1" ]]; then
    echo "[ship] force-pushing to origin/$BRANCH (with --force-with-lease)..."
    git push --force-with-lease origin HEAD
  else
    echo "[ship] pushing to origin/$BRANCH..."
    git push origin HEAD
  fi
else
  echo "[ship] origin/$BRANCH already at HEAD — skipping push."
fi

if [[ "${SKIP_BUILD:-}" == "1" ]]; then
  echo "[ship] SKIP_BUILD=1 — stopping after push."
  exit 0
fi

# ─── 4) Trigger Cloud Build, retrying on transient FAILED_PRECONDITION ───
BUILD_ID=""
for ((i=1; i<=TRIGGER_MAX_RETRIES; i++)); do
  if BUILD_ID=$(gcloud builds triggers run "$TRIGGER_NAME" \
        --project="$BUILD_PROJECT" --region="$REGION" --branch="$BRANCH" \
        --format='value(metadata.build.id)' 2>/tmp/luz-ship-trigger.err) \
     && [[ -n "$BUILD_ID" ]]; then
    break
  fi
  echo "[ship] trigger attempt $i/$TRIGGER_MAX_RETRIES failed:" >&2
  cat /tmp/luz-ship-trigger.err >&2 || true
  if (( i < TRIGGER_MAX_RETRIES )); then
    echo "[ship] retrying in ${TRIGGER_RETRY_SECONDS}s..." >&2
    sleep "$TRIGGER_RETRY_SECONDS"
  fi
done
if [[ -z "$BUILD_ID" ]]; then
  echo "[ship] ERROR: could not trigger build after $TRIGGER_MAX_RETRIES attempts." >&2
  exit 4
fi
echo "[ship] build started: $BUILD_ID"
echo "[ship] log: https://console.cloud.google.com/cloud-build/builds;region=$REGION/$BUILD_ID?project=$BUILD_PROJECT"

# ─── 5) Poll until terminal ──────────────────────────────────────────────
echo "[ship] polling build (typical 7 min)..."
while :; do
  status=$(gcloud builds describe "$BUILD_ID" \
            --project="$BUILD_PROJECT" --region="$REGION" \
            --format='value(status)' 2>/dev/null || echo "")
  case "$status" in
    SUCCESS|FAILURE|TIMEOUT|CANCELLED|EXPIRED)
      break
      ;;
    "")
      sleep 30
      ;;
    *)
      sleep 30
      ;;
  esac
done
echo "[ship] build finished: status=$status"
if [[ "$status" != "SUCCESS" ]]; then
  exit 5
fi

if [[ "${SKIP_ROLLOUT:-}" == "1" ]]; then
  echo "[ship] SKIP_ROLLOUT=1 — stopping after build."
  exit 0
fi

# ─── 6) Rollout the StatefulSet to the freshly-built image ────────────────
ROLLOUT_SCRIPT="$HOME/.claude/skills/google-skill-rollout-latest/rollout_latest.sh"
if [[ ! -x "$ROLLOUT_SCRIPT" && -f "$ROLLOUT_SCRIPT" ]]; then
  chmod +x "$ROLLOUT_SCRIPT" 2>/dev/null || true
fi
if [[ ! -f "$ROLLOUT_SCRIPT" ]]; then
  echo "[ship] ERROR: rollout script not found at $ROLLOUT_SCRIPT" >&2
  exit 6
fi
echo "[ship] rolling out $STATEFULSET..."
bash "$ROLLOUT_SCRIPT" "$STATEFULSET"
echo "[ship] done. branch=$BRANCH commit=$COMMIT_SHA build=$BUILD_ID statefulset=$STATEFULSET"
