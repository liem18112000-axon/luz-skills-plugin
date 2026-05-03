# luz-skills

Claude Code plugin bundling personal and team skills for Luz / Klara / GKE / Google Cloud workflows, plus a few general-purpose utilities.

**17 skills · cross-platform (`.sh` for POSIX, `.cmd` for Windows)** · install once, update with one command.

## Install

### 1. Add the marketplace + install the plugin

In any Claude Code session, run two slash commands:

```
/plugin marketplace add liem18112000-axon/luz-skills-plugin
/plugin install luz-skills@luz-skills
```

What each does:
- `/plugin marketplace add <owner>/<repo>` — registers this GitHub repo as a marketplace named `luz-skills` (the `name` from `.claude-plugin/marketplace.json`).
- `/plugin install luz-skills@luz-skills` — `<plugin-name>@<marketplace-name>`. Both are `luz-skills` because the marketplace bundles a single plugin of the same name.

### 2. Verify

```
/plugin list
```

Expect a `luz-skills` entry, status `enabled`. Then ask Claude something like *"list the available skills"* — you should see all 15 skill names (`luz-skill-*`, `google-skill-*`, `claude-profile-switcher`, `ngrok-fileserver`, `playwright-klara-earchive`, `java-thetailor-review`).

If a skill is missing, jump to **Troubleshooting** below.

### 3. Install the runtime tools each skill needs

The plugin itself is just `SKILL.md` files + small wrapper scripts — there's nothing to compile or `pip install` *for the plugin*. But individual skills shell out to external CLIs that must be on your `$PATH`:

| Skill family | Required external tools | How to install |
|---|---|---|
| `luz-skill-*` (cache / token / flow-logs / ship) | `kubectl`, `gcloud`, `curl` | `gcloud auth login` + `gcloud components install kubectl`, or install via your OS package manager |
| `luz-skill-flow-logs`, `google-skill-*-logs` | `gcloud` (logs subcommand) | as above |
| `luz-skill-materialize-stats` | `kubectl`, `node` (Node 18+) | brew/apt/winget install nodejs |
| `luz-skill-ship` | `git`, `gcloud`, `kubectl` | as above |
| `google-skill-trigger-cloud-build`, `-rollout-latest` | `gcloud`, `kubectl` | as above |
| `google-skill-gke-configmap` | `kubectl` | as above |
| `playwright-klara-earchive` | `node`, `gcloud` (for the parallel log fetch) + the Playwright MCP server (auto-loaded by Claude Code) | `bootstrap.sh` inside the skill verifies + tries to install where it can |
| `ngrok-fileserver` | `python` (3.10+), `ngrok` (with `ngrok config add-authtoken <TOKEN>`) | `bootstrap.sh` inside the skill verifies + tries to install via `winget` / `brew` / `apt` |
| `claude-profile-switcher` | none (uses Claude Code itself) | — |
| `java-thetailor-review` | none (it's pure code review against `SOUL.md`) | — |

**Bootstrap shortcut.** Skills in the `ngrok/` and `playwright/` groups ship a `bootstrap.sh` (POSIX) and `bootstrap.cmd` (Windows) that probe deps and install via `winget` / `brew` / `apt-get` where available. Run it once after install:

```bash
# POSIX
~/.claude/plugins/luz-skills/skills/ngrok/ngrok-fileserver/bootstrap.sh
~/.claude/plugins/luz-skills/skills/playwright/playwright-klara-earchive/bootstrap.sh
```
```cmd
:: Windows
"%USERPROFILE%\.claude\plugins\luz-skills\skills\ngrok\ngrok-fileserver\bootstrap.cmd"
"%USERPROFILE%\.claude\plugins\luz-skills\skills\playwright\playwright-klara-earchive\bootstrap.cmd"
```

(Plugin install path may differ on your machine — Claude Code prints it on `/plugin install`; check `/plugin list --paths` if unsure.)

### 4. Use it

Skills are invoked by intent — say what you want, Claude picks the matching skill:

| Say this | Claude runs |
|---|---|
| *"ship this branch"* | `luz-skill-ship` |
| *"trigger build for luz-docs"* | `google-skill-trigger-cloud-build` |
| *"flow logs for tenant a5e06d74-..."* | `luz-skill-flow-logs` |
| *"smoke test dev.klara.tech"* | `playwright-klara-earchive` |
| *"share this folder"* | `ngrok-fileserver` |
| *"review this PR"* (in a Java/Quarkus repo) | `java-thetailor-review` |

You can also invoke a skill explicitly with `/<skill-name>` if the slash command is registered.

## Update

When the upstream repo is updated, pull the new version into your local plugin install:

```
/plugin marketplace update luz-skills
```

Claude Code re-syncs the marketplace metadata + skill files. Restart your session (or it'll pick up changes at next session start) and the new SKILL.md content takes effect.

## Uninstall

```
/plugin uninstall luz-skills@luz-skills
/plugin marketplace remove luz-skills
```

The first removes the plugin and all 15 skills; the second forgets the GitHub repo as a marketplace. External tools you installed (`gcloud`, `kubectl`, `node`, `ngrok`, etc.) are left alone.

## Troubleshooting

**"Plugin not found" / "Marketplace not found".** Run `/plugin marketplace list` to confirm `luz-skills` is registered. If not, re-run step 1.

**Some skills don't appear in the available-skills list.** Most likely cause: a typo in `plugin.json`'s `"skills"` array. Check that all 7 paths — `[./skills/luz-skill/, ./skills/google-skill/, ./skills/claude/, ./skills/earchive/, ./skills/ngrok/, ./skills/playwright/, ./skills/code/]` — are listed. Claude Code only auto-discovers skills one level beneath each declared path; nesting deeper (e.g. `skills/luz/luz-skill-foo/SKILL.md`) won't be found unless that intermediate folder is explicitly added to the array.

**Skill runs but fails with "command not found".** The wrapper is OK but the underlying CLI (`gcloud` / `kubectl` / `node` / `ngrok`) isn't on your `$PATH`. See the prereq table above.

**Old version still loaded after `marketplace update`.** Restart Claude Code. Marketplace data refreshes immediately, but already-loaded skills are cached for the current session.

**`bootstrap.sh` says "ngrok authtoken missing".** Sign up free at <https://dashboard.ngrok.com/signup>, copy the authtoken, run `ngrok config add-authtoken <TOKEN>` once.

## What's inside

### Luz / Klara service workflows

| Skill | What it does |
|---|---|
| `luz-skill-get-token` | Acquire an all-tenant admin token from the Luz Security service (port-forwards `services/api-forwarder` if needed; auto-increments local port if busy). |
| `luz-skill-get-cache` | Fetch a `luz_cache` entry by tenant + key. |
| `luz-skill-delete-cache` | Evict a `luz_cache` entry (HTTP DELETE on the same endpoint). |
| `luz-skill-flow-logs` | Interleaved Cloud Logging across the four-service Luz request flow: `luz-webclient → luz-docs-view-controller → luz-docs → luz-jsonstore`. Single multi-container `gcloud logging read`, sorted chronologically — perfect for tracing one request end-to-end. |
| `luz-skill-materialize-stats` | Count documents by materialise state (`_hasUnrestrictedFolder` present/absent, restricted-with-codes, restricted-no-codes) for a tenant in dev MongoDB. Mirrors `data/search-effective-security-class.js`, parameterised on `TENANT_ID`. |
| `luz-skill-ship` | End-to-end ship for a Luz feature branch: commit (if staged) → push (if diverged) → trigger Cloud Build → poll until done → rollout the StatefulSet. Idempotent — safe to re-run for build+rollout-only passes. |
| `playwright-klara-earchive` | Hybrid skill: Playwright MCP browser automation + per-step shell helpers. Logs in to `https://dev.klara.tech`, exercises the eArchive page, captures `Custom (N)` / `Documents (N)` counts and folder breakdowns, reloads, reports load timings + screenshots. Auto-handles login pop-up + Session-Terminate recovery. Optional per-step PNG capture. |
| `earchive-data-prepare` | Prepare synthetic eArchive test data for an existing tenant in dev MongoDB. Truncates `documents` + `folders`, generates a folder tree (default 30 folders, max-nested 3 levels) and N documents (default 128 000) with each doc referencing 1–`MAX_FOLDERS_PER_DOC` random folders. Auto-discovers the replica-set primary across `luz-mongodb02-cluster-rs-{0,1,2}` via per-pod port-forward + namespaced probe collection, so the probe never touches real data. |

### Google Cloud / GKE workflows

| Skill | What it does |
|---|---|
| `google-skill-gke-logs` | Read Cloud Logging entries for a single container in a GKE cluster. Org defaults (`klara-nonprod` / `dev` / `europe-west6`) auto-fill cluster, namespace, project. |
| `google-skill-cloudrun-logs` | Read Cloud Logging entries for a Cloud Run service revision (e.g. `dev-luz-thumbnail`). |
| `google-skill-gke-configmap` | View or edit a ConfigMap currently in use by a workload, then `kubectl rollout restart` the workload to pick up the change. View-only is non-destructive. |
| `google-skill-rollout-latest` | Roll a StatefulSet to the most recently uploaded image tag in Google Artifact Registry. Idempotent (no-op restart if already at latest); updates both live spec and `last-applied-configuration` annotation so future `kubectl apply` doesn't compute bogus diffs. |
| `google-skill-trigger-cloud-build` | Kick off a Cloud Build trigger by name. Branch defaults to current git branch; short-circuits if the local HEAD SHA is already the latest tag in GAR. Retries on Bitbucket→Cloud-Build sync-lag errors. |

### Code review

| Skill | What it does |
|---|---|
| `java-thetailor-review` | Brutally direct code review of Java/Quarkus changes against the design principles of `luz_storage`, `luz_storage_batch`, `luz_thumbnail`. Reads `SOUL.md` (the commandments) and applies them to the diff. Cites the violated principle and the file:line in the user's diff. *Not* for non-Java code or non-Quarkus modules (e.g. `luz_docs` is Spring Boot). |

### General-purpose utilities

| Skill | What it does |
|---|---|
| `claude-profile-switcher` | Manage multiple isolated Claude Code subscription profiles on the same machine. Each profile gets its own `CLAUDE_CONFIG_DIR` so credentials, settings, and session history stay isolated. Optional `wire` step generates a `claude_<profile>` shortcut command. **Linux + Windows only** — macOS uses the system Keychain, which bypasses the per-dir trick. |
| `smart-compact-skill-generator` | Generate a custom "smart compact" slash-command tailored to the current conversation. Asks three questions (preserve verbatim / summarize / discard), infers from current context when answers are missing, writes a new skill at `~/.claude/skills/<name>/SKILL.md` with `disable-model-invocation: true` (user-only invocation). The generated skill applies the rules to the conversation and emits a structured summary you can pin or paste forward. |
| `ngrok-fileserver` | Spin up a tiny Python HTTP server with markdown→HTML rendering over a folder, then expose it publicly via ngrok. File-explorer-style table (icon · Name · Size · Type · Modified) + breadcrumb nav + path-search bar (`/__goto`) + in-browser shutdown button (`/__shutdown` POST). Passcode gate (default `18112000`, override with `PASSCODE=…`). Built-in denylist refuses to serve `.ssh`, `.kube`, `.aws`, `.gcloud`, `.claude*`, `.env*`, `*.pem`, `id_rsa*`, `AppData`, etc. — defense in depth. |

## Layout

Skills are grouped by domain into 6 sub-directories under `skills/`. Each sub-directory is listed explicitly in `plugin.json` so Claude Code's plugin loader (which only auto-discovers one level beneath each declared path) can find them:

```
.claude-plugin/
  plugin.json        # "skills": [./skills/luz-skill/, ./skills/google-skill/, …] (7 paths)
  marketplace.json   # marketplace listing — what `/plugin install` reads
skills/
  luz-skill/         # 6 skills — Luz / Klara / KLARA backend workflows
    luz-skill-delete-cache/   SKILL.md + delete_cache.{sh,cmd}
    luz-skill-flow-logs/      SKILL.md + trace_flow_logs.{sh,cmd}
    luz-skill-get-cache/      SKILL.md + get_cache.{sh,cmd}
    luz-skill-get-token/      SKILL.md + get_token.{sh,cmd}
    luz-skill-materialize-stats/  SKILL.md + check_materialize.{sh,cmd,js}
    luz-skill-ship/           SKILL.md + ship.{sh,cmd}
  google-skill/      # 5 skills — Google Cloud / GKE
    google-skill-cloudrun-logs/       SKILL.md + view_cloudrun_logs.{sh,cmd}
    google-skill-gke-configmap/       SKILL.md + view_configmap.{sh,cmd}
    google-skill-gke-logs/            SKILL.md + view_logs.{sh,cmd}
    google-skill-rollout-latest/      SKILL.md + rollout_latest.{sh,cmd}
    google-skill-trigger-cloud-build/ SKILL.md + trigger_build.{sh,cmd}
  claude/            # 2 skills — Claude Code utilities
    claude-profile-switcher/      SKILL.md + claude_profile.{sh,cmd}
    smart-compact-skill-generator/  SKILL.md
  earchive/          # 1 skill — eArchive (Klara) MongoDB tooling
    earchive-data-prepare/    SKILL.md + bootstrap.{sh,cmd} + prepare.{sh,cmd} + _lib/prepare_data.js
  ngrok/             # 1 skill — ngrok-based file sharing
    ngrok-fileserver/         SKILL.md + bootstrap.{sh,cmd} + serve.{sh,cmd} + _lib/server.py
  playwright/        # 1 skill — Playwright browser automation
    playwright-klara-earchive/  SKILL.md + bootstrap.{sh,cmd} + step_*.{sh,cmd} + _lib/*.js
  code/              # 1 skill — code review tooling
    java-thetailor-review/    SKILL.md + SOUL.md
```

Every skill follows the same shape: a `SKILL.md` with YAML frontmatter (`name` + `description`) plus a body that's the assistant's playbook for invoking it. Most also ship cross-platform runners so the same skill works from Git Bash on Windows, zsh on macOS, and bash on Linux. Skills with non-trivial parsing keep shared logic in `_lib/*.js` (Node) or `_lib/*.py` (Python) — both wrappers shell out to a single source of truth.

## For maintainers — adding or editing a skill

Edit the `SKILL.md` (or its runner scripts) in the appropriate group folder, commit, push. Consumers run `/plugin marketplace update luz-skills` to pull the new version; new sessions pick it up automatically.

To add a brand-new group (e.g. `kubernetes/`), create the directory under `skills/` and add its path to `.claude-plugin/plugin.json`'s `"skills"` array — the loader doesn't recurse, so each parent directory must be listed explicitly.

## Conventions

- **Cross-platform**: `.sh` for POSIX (Git Bash / macOS / Linux), `.cmd` for Windows native (cmd / PowerShell). Where logic is non-trivial, both wrappers shell out to a shared `_lib/*.js` (Node) or `_lib/*.py` (Python) so there's one source of truth.
- **Org defaults**: Klara skills default to `klara-nonprod` / `dev` / `europe-west6`. Always overridable via env vars or `KEY=VALUE` arguments. The skill prints the resolved tuple before running so you can sanity-check.
- **Bootstrap when needed**: skills that have external deps (`ngrok-fileserver`, `playwright-klara-earchive`) ship a `bootstrap.{sh,cmd}` that verifies + installs via `winget` / `brew` / `apt-get` where possible, and exits non-zero with manual install instructions when it can't.

## Repo

<https://github.com/liem18112000-axon/luz-skills-plugin>