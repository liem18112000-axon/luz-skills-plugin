---
name: playwright-klara-earchive
description: Use Playwright MCP to log in to https://dev.klara.tech and exercise the eArchive page — capture "Custom (N)" / "Documents (N)" counts, list each "<folder> — N Files" pair, count the document items actually rendered under Documents, reload once, and report wall-clock load durations for both visits. Auto-handles the login pop-up and the "Session Terminate" → "Continue my session" recovery. Combine with luz-skill-flow-logs / google-skill-gke-logs to diagnose backend failures. Use when the user asks to "test eArchive on dev", "run the klara playwright check", "exercise the eArchive page", "smoke test dev.klara.tech", or any equivalent. Bash-only; Windows users run via Git Bash or `bash` from PowerShell (one-time `ensure-bash.ps1` bootstrap).
---

# playwright-klara-earchive

End-to-end browser exercise of the **eArchive** page on `https://dev.klara.tech`. The skill is a hybrid: Playwright MCP tool calls (issued by the assistant) for browser actions, plus per-step shell scripts (POSIX + Windows) for everything else — timing, snapshot parsing, log fetching, log summarising. The assistant orchestrates by alternating MCP turns with `Bash` calls into `step_*.sh` / `step_*.cmd`.

The skill captures, in this order:

1. Wall-clock load time for the **first** visit to eArchive (after the click on the left-nav folder icon).
2. The number rendered in the **Custom (N)** badge.
3. The number rendered in the **Documents (N)** badge.
4. For each folder in the folder widget: `<folder name> — <N> Files`.
5. The actual count of document items rendered under the **Documents** section.
6. Wall-clock load time for the **second** visit (after an explicit reload, fired ≤15 s after Step 4 completes).
7. For the first `FOLDER_DRILL_COUNT` folders (default 5): click into each, time the click→render, capture the in-folder Documents badge and rendered-item count.

Auto-handled interruptions:

- **Login pop-up** on the landing page — fills email + password and submits.
- **"Session Terminate" dialog** mid-flow — clicks "Continue my session", logs in again, restarts from the top.

## Inputs

| Var | Required? | Default |
| --- | --- | --- |
| `URL`         | optional      | `https://dev.klara.tech/` |
| `EMAIL`       | optional      | `liem18112000@gmail.com` |
| `PASSWORD`    | **required**  | (no default — pass via env var or args at invocation; never commit to disk) |
| `RELOADS`     | optional      | `1` |
| `FOLDER_DRILL_COUNT` | optional | `5` — number of folders to click into and time after the reload step. `0` to skip. |
| `SCREENSHOTS` | optional      | `yes` (per-step PNGs into a temp folder; absolute path printed at end). Set to `no` to skip. |

Mask the password when echoing the resolved tuple.

## Headless mode (optional)

Default: **visible browser UI** — easier to debug hangs, slow loads, Session Terminate dialogs by glancing at the window.

To run headless instead, edit `~/.claude.json` (or the equivalent on your OS) and add `--headless` to the Playwright MCP server's `args`:

```json
"playwright": {
  "type": "stdio",
  "command": "npx",
  "args": ["-y", "@playwright/mcp@latest", "--headless"],
  "env": {}
}
```

Then `/exit` and relaunch Claude Code (MCP servers boot once at startup; can't be flipped mid-session). Remove the flag and relaunch to go back to visible UI. Headless trades visual debuggability for slightly faster start and lower CPU — only worth it for batch / CI / scripted runs.

## Files in this skill

```
playwright-klara-earchive/
├── SKILL.md                    (this file — assistant playbook)
├── ensure-bash.ps1               (one-time Windows bash bootstrap — installs Git for Windows via winget if bash is missing)
├── bootstrap.sh                  (Step 0 — verify deps, install where possible)
├── step_init_screenshot_dir.sh   (Step 0b — mint <cwd>/.playwright-mcp/screenshots-<epoch>/, print absolute path)
├── step_mark_time.sh             (emit Date.now() — t0/t1/t2/t3 marks)
├── step_kick_logs.sh             (kick luz-skill-flow-logs in BACKGROUND, print log path)
├── step_extract_tenant.sh        (first UUID from a DOM dump, stdin or file)
├── step_parse_snapshot.sh        (extract counts + folders + doc-item count from snapshot YAML)
├── step_summarize_logs.sh        (count anomaly patterns in the background log file)
└── _lib/
    ├── parse_snapshot.js
    ├── extract_tenant.js
    └── summarize_logs.js
```

## Operating mode

**AUTONOMOUS.** No inter-step pauses. Print one-line status updates per step. Only halt on hard blockers (rejected password without fallback, network unreachable, missing deps that bootstrap couldn't install).

## Parallelisation

The gcloud log fetch is the longest single step (~60–90 s). Kick it off **in the background** the moment the tenant UUID is known (end of Step 4) so it overlaps Step 5 and is ready by Step 7.

```
time →
  Step 0     bootstrap        ▓
  Step 1-3   login + load #1   ▓▓▓▓▓▓
  Step 4     parse + extract       ▓▓
  Step 4b    kick flow-logs (BG)     ░░░░░░░░░░░░░░░  (run_in_background)
  Step 5     reload + load #2        ▓▓▓▓▓▓▓▓▓▓
  Step 7     summarise + report                       ▓▓
                                          ▲ logs already done by here
```

## Assistant playbook

Path: `~/.claude/skills/playwright-klara-earchive/` (use this on every platform — bash-only). On Windows, run via Git Bash, or invoke from PowerShell as `bash ~/.claude/skills/playwright-klara-earchive/<script>.sh ARGS`. First-time Windows setup if `bash` is not on PATH yet: `powershell -ExecutionPolicy Bypass -File ~/.claude/skills/playwright-klara-earchive/ensure-bash.ps1`.

### Step 0 — Bootstrap deps + (if SCREENSHOTS=yes) mint per-run screenshot dir

```
Bash { command: "~/.claude/skills/playwright-klara-earchive/bootstrap.sh" }
```

If exit 1, surface the printed instructions and stop. The script tries `winget` / `brew` / `apt-get` etc. for `node`. `gcloud` always requires manual install (interactive auth).

**If `SCREENSHOTS=yes` (default):**

```
Bash { command: "~/.claude/skills/playwright-klara-earchive/step_init_screenshot_dir.sh" }
  → prints absolute path to <cwd>/.playwright-mcp/screenshots-<epoch-ms>/
```

The dir lives **inside `.playwright-mcp/`** because the Playwright MCP server only allows writes under the project dir and that subfolder. Writing to `os.tmpdir()` fails with `File access denied: <path> is outside allowed roots`.

Capture that path into a local var (call it `SHOT_DIR`). For every later step that warrants visual evidence, call:

```
mcp__playwright__browser_take_screenshot {
  type: "png",
  filename: "<SHOT_DIR>/stepNN-<short-name>.png",
  fullPage: true
}
```

Take screenshots after — not before — each MCP action so the captured frame reflects the resulting state. Suggested naming:

| # | Filename                              | When to capture |
|---|---------------------------------------|----------------|
| 01 | `step01-landing.png`                 | After Step 1 navigate (Keycloak / dashboard) |
| 02 | `step02-after-login.png`             | After Step 2 click + wait_for "eArchive" |
| 03 | `step03-earchive-load1.png`          | After Step 3 wait_for returns (fully rendered) |
| 04 | `step04-snapshot-context.png`        | After Step 4 snapshot save (visual sanity check) |
| 05 | `step05-after-reload.png`            | After Step 5 wait_for returns |
| 06 | `step06-session-terminate.png`       | Only if Step 6 fires |
| 99 | `step99-final.png`                   | Right before printing the report |

If `SCREENSHOTS=no`, skip every `browser_take_screenshot` call and skip the `step_init_screenshot_dir` call.

### Step 1 — Open the page

```
mcp__playwright__browser_navigate { url: <URL> }
mcp__playwright__browser_snapshot
```

### Step 2 — Handle the login pop-up if it appears

If the snapshot shows email/password textboxes:

```
mcp__playwright__browser_fill_form { fields: [
  { name: "Email",    type: "textbox", target: "<email-ref>",    value: <EMAIL> },
  { name: "Password", type: "textbox", target: "<password-ref>", value: <PASSWORD> }
]}
mcp__playwright__browser_click { element: "Sign in / Login button", target: "<button-ref>" }
mcp__playwright__browser_wait_for { text: "eArchive" }
```

### Step 3 — Click "eArchive" in the left nav, time load #1

```
Bash { command: "~/.claude/skills/playwright-klara-earchive/step_mark_time.sh" }
  → captures t0

mcp__playwright__browser_click  { element: "eArchive nav item", target: "<ref>" }
mcp__playwright__browser_wait_for { text: "Manage access rights" }   # visible button — DO NOT use "Documents" (a11y reports the heading hidden)

Bash { command: "~/.claude/skills/playwright-klara-earchive/step_mark_time.sh" }
  → captures t1
load1_ms = t1 - t0
```

### Step 4 — Snapshot, parse, kick logs in the background

```
mcp__playwright__browser_snapshot { filename: "earchive-load1.yml" }
```

Then parse + extract tenant + start log fetch concurrently:

```
Bash { command: "~/.claude/skills/playwright-klara-earchive/step_parse_snapshot.sh ./.playwright-mcp/earchive-load1.yml" }
  → JSON: { customCount, documentsCount, documentItemCount, folderRows[] }

mcp__playwright__browser_evaluate {
  function: "() => document.documentElement.outerHTML",
  filename: "dom.txt"
}
Bash { command: "~/.claude/skills/playwright-klara-earchive/step_extract_tenant.sh ./.playwright-mcp/dom.txt" }
  → tenant UUID (one line)

Bash {
  command: "~/.claude/skills/playwright-klara-earchive/step_kick_logs.sh <TENANT_UUID>",
  run_in_background: true
}
  → prints the log file path on stdout (capture it from the bash result)
```

`step_kick_logs.sh` exits immediately after backgrounding `luz-skill-flow-logs` with `FRESHNESS=10m SEVERITY=ERROR LIMIT=2000`. Capture the output path so Step 7 can read it.

### Step 5 — Reload, time load #2 (≤15 s after Step 4)

Fire immediately. If you exceed 15 s, note in **Anomalies**.

```
Bash { command: "~/.claude/skills/playwright-klara-earchive/step_mark_time.sh" }   → t2
mcp__playwright__browser_navigate { url: <current-url> }
mcp__playwright__browser_wait_for { text: "Manage access rights" }
Bash { command: "~/.claude/skills/playwright-klara-earchive/step_mark_time.sh" }   → t3
load2_ms = t3 - t2
```

For `RELOADS > 1`, repeat (still ≤15 s gap between iterations) and report each.

### Step 5b — Drill into the first `FOLDER_DRILL_COUNT` folders

Goal: confirm each folder actually opens, time the click→render, and capture the rendered doc count vs the badge in the folder row. Verifies the per-folder query path on top of the page-level load already measured.

`folderRows` from Step 4's parse output already carries `{ name, files, ref }`. Skip rows whose `ref` is `null` (synthesised entries) and skip the literal company-root row (`Best Company GmbH` / first row with `files === "0"`). Take the first `FOLDER_DRILL_COUNT` of the remaining rows.

For each picked folder:

```
Bash { command: "~/.claude/skills/playwright-klara-earchive/step_mark_time.sh" }   → t_a

mcp__playwright__browser_click {
  element: "folder row: <folder.name>",
  target: "<folder.ref>"
}
mcp__playwright__browser_wait_for { text: "<folder.name>" }   # folder name appears in breadcrumb / page title
mcp__playwright__browser_wait_for { textGone: "Loading" }     # belt-and-braces; ignored if "Loading" never showed

Bash { command: "~/.claude/skills/playwright-klara-earchive/step_mark_time.sh" }   → t_b
folder_load_ms = t_b - t_a

mcp__playwright__browser_snapshot { filename: "earchive-folder-<idx>.yml" }
Bash { command: "~/.claude/skills/playwright-klara-earchive/step_parse_snapshot.sh ./earchive-folder-<idx>.yml" }
  → JSON: { documentsCount, documentItemCount, ... }   # documentsCount is the filtered-to-folder badge
```

Record `{ name, badgeFiles (from Step 4), inFolderDocumentsCount, inFolderRenderedItems, loadMs }` per folder.

After each drill, return to the eArchive root before the next click. Two options:

```
mcp__playwright__browser_navigate { url: <eArchive-url> }
mcp__playwright__browser_wait_for { text: "Manage access rights" }
```

(Slow but reliable. A breadcrumb / "back to eArchive" link is preferable when the snapshot exposes one — surface it as `<ref>` and click instead of navigating.)

If `FOLDER_DRILL_COUNT === 0`, skip this step entirely.

### Step 6 — Session-Terminate recovery

If a snapshot at any point shows "Session Terminate" / "Session expired":

1. `mcp__playwright__browser_click` on "Continue my session".
2. Re-run **Step 2** when the login form reappears.
3. Restart from **Step 3**, discard half-measured timings, note in Anomalies.

### Step 7 — Drain background logs, write report

```
Bash { command: "~/.claude/skills/playwright-klara-earchive/step_summarize_logs.sh <log-file-path-from-step-4b>" }
  → JSON: { mongoSocketReadException, archivesDirectoriesBranded500, distinct500Targets, ... }
```

If the background process is still running, wait for the BashOutput notification — do not poll.

Print a structured summary:

```
URL:     https://dev.klara.tech/
Account: liem18112000@gmail.com
Tenant:  <UUID>

Load timings
  First load  (after eArchive click): <load1_ms> ms
  Second load (after reload):         <load2_ms> ms

Counts
  Custom    (N): <customCount>
  Documents (N): <documentsCount>
  Documents rendered under widget:    <documentItemCount>   <-- mark MISMATCH if != documentsCount

Folder widget
  <folder-1>: <N> Files
  <folder-2>: <N> Files
  ...

Folder drill (first <FOLDER_DRILL_COUNT>)
  <folder-1>: load=<ms>ms badge=<N> filtered-Documents=<N> rendered=<N>
  <folder-2>: load=<ms>ms badge=<N> filtered-Documents=<N> rendered=<N>
  ...
  (skipped if FOLDER_DRILL_COUNT=0)

Anomalies (from logs + flow)
  - MongoSocketReadException × <N> on luz-jsonstore aggregate
  - <K> 5xx on /archives/directories/branded
  - Session terminated during step X — recovered.   (only if it happened)
  - Step 5 reload fired <S> s after Step 4         (only if > 15)

Screenshots
  <SHOT_DIR-absolute-path>      (only if SCREENSHOTS=yes)
    └── stepNN-*.png  ×  <count>
```

When `SCREENSHOTS=yes`, the **last line of the report MUST be the absolute path** of the screenshot folder so the user can paste it into a file explorer / `start "" "<path>"` directly. Don't hide it in the middle. Run `ls -la "<SHOT_DIR>"` before printing if you want the file count + sizes.

## Notes

- The Playwright MCP browser session is persistent across calls within a single Claude Code session — once logged in, you stay logged in until "Session Terminate" or `mcp__playwright__browser_close`.
- Mask the password when echoing the resolved tuple. Don't take a `browser_take_screenshot` of the login form. Don't paste it into log queries or commit messages.
- Snapshot first, click second. Selectors look right in HTML but Playwright needs accessibility-tree refs.
- `wait_for { text: "Manage access rights" }` is the canonical post-load marker — `Documents` and `Custom` headings are wrapped in `<b>` and reported `hidden` by the a11y tree, so `wait_for "Documents"` will time out even on a fully-rendered page.
- "First visit" timing measures in-app navigation (click → render). "Second visit" measures full reload (network → render). Report both clearly labelled rather than averaging.
