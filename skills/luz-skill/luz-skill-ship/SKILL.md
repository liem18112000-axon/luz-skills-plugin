---
name: luz-skill-ship
description: Commit (if staged) → push (if local diverges) → trigger Cloud Build → poll until done → rollout the StatefulSet to the new image. End-to-end ship for a Luz feature branch in one command. Use when the user wants to "ship this", "commit and deploy", "build and rollout", or any equivalent. The skill auto-skips commit when nothing is staged and auto-skips push when origin already matches HEAD, so it is also safe to re-run for a build+rollout-only pass (e.g. after a manual squash + force-push). Commit message is mandatory only when staged changes are being committed; it goes in verbatim with no AI / Co-Authored-By trailer. Set `FORCE_PUSH=1` after a squash/amend to push with `--force-with-lease`. The skill DOES NOT run `git add` for you (won't sweep up unrelated dirty files); stage what you want first. Defaults to trigger=`luz-docs`, statefulset=`luz-docs`. Retries the build trigger on transient `FAILED_PRECONDITION: Couldn't read commit` errors caused by Bitbucket→Cloud Build sync lag. Cross-platform — ships a Windows .cmd wrapper and a POSIX .sh runner.
---

# luz-skill-ship

Bundles the four-step end-of-iteration flow we run repeatedly:

1. `git commit -m "<message>"` (already-staged changes; **no AI / Co-Authored-By trailer**)
2. `git push origin HEAD`
3. `gcloud builds triggers run <trigger> --branch=<current>` (with retry on Bitbucket sync lag)
4. Poll the build until SUCCESS / FAILURE
5. On SUCCESS: shell out to `google-skill-rollout-latest` to update the StatefulSet to the new image

Failure at any step exits non-zero with a clear marker so you know where it stopped.

## Why it doesn't `git add` for you

In a typical session your working tree has dirty unrelated files (local `.gitignore`, `docker-compose.yml` overrides, helper scripts under `data/`). A `git add -A` would sweep those into the commit. The skill instead requires you to stage what you want with `git add <paths>` first; if nothing is staged it errors out.

## Inputs

| Var | Required? | Default |
| --- | --- | --- |
| `MESSAGE`               | **only when staged** (1st positional or env) — exact commit message |
| `FORCE_PUSH`            | optional | unset → regular push; `1` → `git push --force-with-lease` (after squash/amend) |
| `TRIGGER_NAME`          | optional | `luz-docs` |
| `STATEFULSET`           | optional | `luz-docs` |
| `BRANCH`                | optional | output of `git rev-parse --abbrev-ref HEAD` |
| `BUILD_PROJECT`         | optional | `klara-infra` |
| `REGION`                | optional | `europe-west6` |
| `TRIGGER_RETRY_SECONDS` | optional | `30` — pause between retries on `Couldn't read commit` |
| `TRIGGER_MAX_RETRIES`   | optional | `6` |
| `SKIP_BUILD`            | optional | `1` → stop after push (useful for "just commit + push") |
| `SKIP_ROLLOUT`          | optional | `1` → stop after build (useful for "build but don't deploy yet") |

## How to gather inputs

1. Parse `KEY=VALUE` args. The commit message may also be a bare positional arg.
2. **Always** ask for `MESSAGE` if missing — there is no safe default.
3. **Never** add the `Co-Authored-By: Claude` trailer to the commit message. The user has explicitly forbidden it.
4. If the user has unrelated dirty files, surface the existing staged set with `git diff --cached --name-only` and ask for confirmation before invoking the skill.

## How to invoke

### Linux / macOS / Git Bash
Path: `~/.claude/skills/luz-skill-ship/ship.sh`

```bash
# Common case
git add src/main/java/ch/klara/luz/docs/materialize/MaterializeFacade.java
git add src/main/java/ch/klara/luz/docs/service/jsonstore/JsonStoreMongoService.java
~/.claude/skills/luz-skill-ship/ship.sh "[LUZ-152936] Cache list-count in queryDocumentCollectionWithFacet"

# Just commit + push, skip build/rollout
SKIP_BUILD=1 ~/.claude/skills/luz-skill-ship/ship.sh "wip"

# Build but don't rollout (useful for review)
SKIP_ROLLOUT=1 ~/.claude/skills/luz-skill-ship/ship.sh "[LUZ-152936] try a thing"

# Different StatefulSet / trigger
STATEFULSET=luz-docs-process TRIGGER_NAME=luz-docs-process \
  ~/.claude/skills/luz-skill-ship/ship.sh "[LUZ-200000] process fix"
```

### Windows native cmd / PowerShell
Path: `%USERPROFILE%\.claude\skills\luz-skill-ship\ship.cmd` — shells out to bash.

## What the script does

1. Resolves `MESSAGE` (positional > env). Errors out if missing.
2. Resolves `BRANCH` from `git rev-parse --abbrev-ref HEAD` if not pinned. Errors out on detached HEAD.
3. Verifies there is at least one staged change (`git diff --cached --quiet` returns non-zero).
4. Prints the staged file list, then commits with the exact `MESSAGE` — **no AI / co-author trailer is appended**.
5. Pushes `HEAD` to `origin/<BRANCH>`.
6. Calls `gcloud builds triggers run <TRIGGER_NAME> --branch=<BRANCH>`. On transient `FAILED_PRECONDITION: Couldn't read commit` (Bitbucket sync lag), retries up to `TRIGGER_MAX_RETRIES` times spaced `TRIGGER_RETRY_SECONDS` apart.
7. Polls `gcloud builds describe <id>` every 30 s until status is terminal (`SUCCESS`, `FAILURE`, `TIMEOUT`, `CANCELLED`, `EXPIRED`). Prints the Cloud Build console URL up front.
8. On SUCCESS: shells out to `~/.claude/skills/google-skill-rollout-latest/rollout_latest.sh <STATEFULSET>` to update the live image. On non-success: exits 5.
9. Prints a final summary line: `branch=… commit=… build=… statefulset=…`.

## Caveats

- **No co-author trailer.** The user has been explicit. If you ever need to override (other repos / contexts), call `git commit` directly with the appropriate trailer instead of using this skill.
- **Trigger must accept the branch.** The default `luz-docs` trigger is push-locked to `^master$` but accepts manual `--branch=` overrides (see existing `git ls-remote` history for proof). For other triggers verify they accept the branch.
- **Build cache.** This skill does NOT short-circuit when local HEAD already matches the latest GAR tag. If you want that, run `~/.claude/skills/google-skill-trigger-cloud-build/trigger_build.sh` instead.
- **Rollout step needs `google-skill-rollout-latest` installed.** It usually is; the skill errors out cleanly if missing.
