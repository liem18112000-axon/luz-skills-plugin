---
name: earchive-data-prepare
description: Prepare synthetic eArchive test data for an existing Luz tenant in dev MongoDB. Truncates `documents` + `folders`, then generates a folder tree (default 30 folders, max-nested 3 levels) and N documents (default 128 000) where each doc references 1–`MAX_FOLDERS_PER_DOC` random folders (default 10). Auto-discovers the replica set primary across `luz-mongodb02-cluster-rs-{0,1,2}` by spinning a kubectl port-forward to each in turn and probing with a one-shot insert+drop on a namespaced probe collection (`_earchive_data_prepare_probe`) — so the probe never touches real data. Bootstrap-installs `node` + the `mongodb` npm package on first run; `kubectl` must already be on PATH. Bash-only; Windows users run via Git Bash or `bash` from PowerShell (one-time `ensure-bash.ps1` bootstrap). Use when the user asks to "seed test data on dev tenant", "regenerate folder/doc fixtures", "prepare 128k docs for the canary tenant", or any equivalent.
---

# earchive-data-prepare

Wipes `folders` + `documents` for a Luz tenant and regenerates fresh synthetic fixtures sized for performance testing of the eArchive page (materialise / counter / facet / list paths). Single command, end to end.

## Inputs

| Var | Required? | Default |
| --- | --- | --- |
| `TENANT_ID`            | optional      | `a5e06d74-137c-4a9e-9adc-9eccdccc2d17` (dev canary) |
| `DOC_COUNT`            | optional      | `128000` |
| `FOLDER_COUNT`         | optional      | `30` |
| `MAX_NESTED`           | optional      | `3` (folder tree max depth: root = 0, deepest = `MAX_NESTED-1`) |
| `MAX_FOLDERS_PER_DOC`  | optional      | `10` (each doc references 1..N random folders) |
| `BATCH_SIZE`           | optional      | `1000` (insertMany batch size for documents; also bulkWrite batch for materialize step) |
| `MATERIALIZE`          | optional      | `true` (after generate, stamp `_effectiveSecurityClassCodes`, `_hasPublicFolder`, `_folderNames` on every fresh doc — mirrors `MaterializeStateComputer.compute`). Set `0` / `false` / `no` to skip. |
| `RESTRICTED_FOLDER_PCT`| optional      | `75` (probability, 0–100, that a generated folder gets non-empty `securityClassCodes` from the built-in code pool — `CONFIDENTIAL`, `INTERNAL`, `SECRET`, `HR`, `FINANCE`, `LEGAL`, `EXEC`. Each restricted folder gets 1–3 random codes; `inheritedSecurityClassCodes` propagates parent's union. `0` = all folders open, `100` = every folder restricted.) |
| `NAMESPACE`            | optional      | `dev-mongodb-clusters` |
| `STS_NAME`             | optional      | `luz-mongodb02-cluster-rs` (replica StatefulSet base name; `-0/-1/-2` suffixes appended) |
| `PORT`                 | optional      | `27017` |
| `CONFIRM`              | **required**  | must be set to `yes` to perform the truncate + regenerate. Without it, the script prints what it would do and exits non-zero. |

## How to invoke

### Invocation (bash)

Path: `~/.claude/skills/earchive-data-prepare/prepare.sh`

Linux / macOS: run directly. Windows: run via Git Bash, or invoke from PowerShell as `bash ~/.claude/skills/earchive-data-prepare/prepare.sh ARGS`.

First-time Windows setup (only if `bash` is not on PATH yet):
`powershell -ExecutionPolicy Bypass -File ~/.claude/skills/earchive-data-prepare/ensure-bash.ps1`

Then the bash examples below work from any shell.

```bash
~/.claude/skills/earchive-data-prepare/prepare.sh                                # dry-run (refused: missing CONFIRM)
CONFIRM=yes ~/.claude/skills/earchive-data-prepare/prepare.sh                    # default sizes
CONFIRM=yes DOC_COUNT=50000 FOLDER_COUNT=20 MAX_NESTED=2 \
    ~/.claude/skills/earchive-data-prepare/prepare.sh                            # custom sizes
CONFIRM=yes TENANT_ID=<uuid> ~/.claude/skills/earchive-data-prepare/prepare.sh   # different tenant
```

## What it does, in order

1. **Bootstrap** — checks `node`, `kubectl` on PATH; installs `node` via the host package manager when possible (`winget` / `brew` / `apt-get`); installs `mongodb` npm package into `_lib/node_modules` if missing. Errors out clearly when it can't auto-install (e.g., no `kubectl` — manual install required).
2. **Replica probe loop** — for `idx` in `0,1,2`:
   1. Tear down any prior `kubectl port-forward` on `PORT`.
   2. `kubectl port-forward <STS>-<idx> <PORT>:<PORT> -n <NAMESPACE>` in the background.
   3. Wait up to 10 s for `localhost:<PORT>` to accept TCP.
   4. Connect with `directConnection=true` (so the driver talks only to this replica) and execute the **probe**: insert one doc into `_earchive_data_prepare_probe`, then drop the entire collection. Probe collection is *not* `documents` / `folders`; it can never collide with real data.
   5. Insert succeeds → this replica is the primary; break.
   6. Mongo error 10107 / `not master` → tear down and try next.
3. **Refuse without CONFIRM=yes** — print the resolved tuple + exit 1.
4. **Truncate** `folders` and `documents` via `deleteMany({})`. Indexes survive (preserves anything `create-materialize-indexes.js` installed).
5. **Generate folders** — flat array; first ~`ceil(FOLDER_COUNT / 2^MAX_NESTED)` are roots (depth 0), rest pick a random parent at depth `< MAX_NESTED-1`. Empty `securityClassCode` + `inheritedSecurityClassCode` (all unrestricted — exercises the "open" branch of the gate). `parentFolderId` set / `null` for roots.
6. **Generate documents** — in batches of `BATCH_SIZE`. Each doc: random UUID `_id`, `folderIds` = 1..`MAX_FOLDERS_PER_DOC` distinct random folder ids, `_updatedDate = now`, `_deletionStatus = "false"`, `name = doc-<idx>`. No materialise fields stamped here; the next step handles them.
7. **Materialize** (when `MATERIALIZE != 0/false/no`, default on) — pre-cache all folders, then bulk-write per-doc:
   - `_effectiveSecurityClassCodes` = union of each referenced folder's `securityClassCodes` + `inheritedSecurityClassCodes`. Empty when no folders or all folders are open.
   - `_hasPublicFolder` = `true` if any referenced folder has both own + inherited codes empty.
   - `_folderNames` = distinct names of all referenced folders.
   Mirrors `MaterializeStateComputer.compute` 1:1. Skip with `MATERIALIZE=0` if you specifically want to test the backfill path.
8. **Cleanup** — kill the kubectl port-forward; print pre/post counts + elapsed time.

## Files in this skill

```
earchive-data-prepare/
├── SKILL.md                 (this file)
├── ensure-bash.ps1          (one-time Windows bash bootstrap — installs Git for Windows via winget if bash is missing)
├── prepare.sh               (orchestrator: bootstrap → port-forward loop → generate → cleanup)
├── bootstrap.sh             (deps check + install where possible)
└── _lib/
    ├── prepare_data.js      (the actual probe + truncate + generate; cross-platform Node)
    └── package.json         (declares `mongodb` dep)
```

## Notes

- The probe collection name `_earchive_data_prepare_probe` is intentional — leading underscore + skill name + `_probe`. If a previous run crashed mid-probe and left the collection, the next run will just overwrite + drop it. Safe to ignore or hand-drop.
- Default sizing (128 K docs / 30 folders / 1–10 per doc) hits ~3.3M `folderIds` array entries — well within the canary tenant's existing capacity. Adjust `DOC_COUNT` for stress runs.
- The skill **does not** restart luz-docs or invalidate any cache. With `MATERIALIZE=true` (default), fresh docs are stamped in-band so the eArchive page works immediately on the next request. With `MATERIALIZE=0`, the backfill picks them up on its next trigger cycle (every 60 min by default; throttle key in `luz-cache`). To force the backfill sooner, evict the throttle key via `luz-skill-delete-cache` and trigger any write to the tenant.
- All inserts are unordered (`{ ordered: false }`) — single doc failures don't abort the batch. Errors print at the end; partial generation is recoverable by re-running.
