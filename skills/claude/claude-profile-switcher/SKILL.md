---
name: claude-profile-switcher
description: Manage multiple isolated Claude Code subscription profiles on the same machine and switch between them. Use when the user asks to "set up my claude profiles", "add a new claude account", "switch claude account", "use my work claude account", "log in as a different claude", "create claude_<name> shortcut command", "wire shortcut commands", or wants to run multiple `claude` sessions in parallel each authenticated as a different subscription. Works by giving each profile its own `CLAUDE_CONFIG_DIR`, so credentials, settings, and session history stay isolated. Optional `wire` step generates a `claude_<profile>` shortcut command per profile so you can launch claude under a profile without remembering the switcher path. Linux + Windows. macOS not supported (Claude Code stores credentials in the system Keychain there, bypassing the per-dir trick). Bash-only; Windows users run via Git Bash or `bash` from PowerShell (one-time `ensure-bash.ps1` bootstrap).
---

# claude-profile-switcher

Each profile is just a directory under `~/.claude-profiles/<name>/`. The script sets `CLAUDE_CONFIG_DIR=<that-dir>` for the duration of a child shell or `claude` invocation, so two parallel terminals can be logged in as two different subscriptions at once.

`CLAUDE_CONFIG_DIR` is community-confirmed (Claude Code GitHub issues #25762 and #3833) but not officially documented, so behavior could change in a future release.

---

## Assistant playbook (read this when you, the assistant, are invoked for this skill)

The user typically wants one of three things. Pick the right path, run the listed commands via Bash, and stop after each action that needs the user's hands on a real terminal.

### Path A — "set up my profiles" / "create my claude profiles"

User wants to register N new accounts.

1. **Ask once for the profile names.** Default suggestion: `personal` and `work`. If they already named profiles, use those. Don't ask anything else — names are the only required input.
2. **Create the dirs in one Bash call** (this is safe and auto-approvable):
   ```bash
   ~/.claude/skills/claude-profile-switcher/claude_profile.sh add personal && \
   ~/.claude/skills/claude-profile-switcher/claude_profile.sh add work
   ```
3. **Print the login commands** the user must paste into a real terminal (you cannot do this step for them — `/login` opens a browser). Give them a complete, copy-pasteable block:
   ```bash
   ~/.claude/skills/claude-profile-switcher/claude_profile.sh login personal
   #   inside claude: type /login → finish in browser → /exit

   ~/.claude/skills/claude-profile-switcher/claude_profile.sh login work
   #   inside claude: type /login → finish in browser → /exit
   ```
4. **Warn about the browser gotcha** in one sentence: "log out of Claude.ai between the two `login` runs, OR use a different Chrome profile / Firefox container / incognito window for each — otherwise both profiles end up logged in as the same account."
5. **Stop and wait.** When the user replies "done" or similar, verify with `list` (Bash, auto-approvable):
   ```bash
   ~/.claude/skills/claude-profile-switcher/claude_profile.sh list
   ```

### Path B — "switch to <name>" / "use <name>"

User wants the active shell to use a specific profile.

You **cannot** flip the user's shell from inside this conversation — `use` would `exec` a new shell, which only works in their real terminal. Instead, give them the one-line command:

```bash
~/.claude/skills/claude-profile-switcher/claude_profile.sh use <name>
```

If they want a one-shot run without a subshell, give them this instead:

```bash
~/.claude/skills/claude-profile-switcher/claude_profile.sh run <name>
```

### Path C — "list my profiles" / "what profiles do I have" / "remove <name>"

These are inspection/cleanup tasks. Run them via Bash (auto-approvable, except `remove` which prompts for confirmation):

```bash
~/.claude/skills/claude-profile-switcher/claude_profile.sh list      # inventory
~/.claude/skills/claude-profile-switcher/claude_profile.sh path <n>  # absolute dir
~/.claude/skills/claude-profile-switcher/claude_profile.sh remove <name>  # destructive — confirm with user first
```

For `remove`: always confirm with the user in chat **before** spawning the command, because the script's own y/N prompt won't render well in this UI.

### Path D — "what's the current profile?"

Don't run `current` to answer this. The Bash tool spawns a fresh subshell with no `CLAUDE_CONFIG_DIR`, so it will always say "no profile" — which is misleading. Instead, explain that the active profile is determined by whichever shell the user launched their `claude` from, and offer to run `list` to show available profiles.

### Path E — "create claude_<profile> shortcut command" / "wire shortcuts"

User wants per-profile launcher commands so they can type `claude_liem_epost` instead of the full switcher path. `add` and `remove` already auto-call `wire`, so this path is mostly for an explicit re-wire (e.g. after the user renamed a profile dir by hand).

1. **(Re)wire shortcuts** (Bash, auto-approvable — wire is idempotent):
   ```bash
   ~/.claude/skills/claude-profile-switcher/claude_profile.sh wire
   ```
   `wire` does TWO things:
   - **Generates** `~/.claude-profiles/.shell-init.sh` (POSIX) or `~/.claude-profiles/bin/claude_<name>.cmd` files (Windows), one shortcut per profile.
   - **Activates** automatically — appends one `source` line to `~/.bashrc` and `~/.zshrc` (idempotent), or appends `~/.claude-profiles/bin` to the **User** Path via the `[Environment]::SetEnvironmentVariable` registry API on Windows.

   The user only needs to **open a new terminal** to pick up the change. Don't print manual rc-file/PATH instructions — wire already handled it.

2. **Sanitization rule**: profile name → shortcut name replaces non-alphanumeric chars with `_` (POSIX `sed`) or `-` / `.` / space with `_` (Windows). So `liem-epost` → `claude_liem_epost`.

3. **Args pass through**: `claude_liem_epost --version` is equivalent to running `claude --version` under that profile. The shortcut does NOT replace the user's shell (unlike `use`).

---

## Subcommand reference

| Cmd | What it does | Safe to run via Bash tool? |
| --- | --- | --- |
| `list` (alias `ls`)             | List all profiles. Marks the one matching the current shell's `CLAUDE_CONFIG_DIR` with `*`. | ✅ |
| `add <name>`                    | Create the profile dir. Idempotent (no-op if it exists). Does NOT launch claude. | ✅ |
| `login <name>` (alias `signin`) | Launch `claude` under the profile so the user can `/login`. Interactive — replaces the current process with `claude`. | ❌ — user must run in their own terminal |
| `use <name>` (alias `switch`)   | Replace the current shell with a new one where `CLAUDE_CONFIG_DIR` is exported. | ❌ — only works in user's real shell |
| `run <name> [args…]` (alias `exec`) | Exec `claude` directly under the profile (one-shot). | ❌ — interactive |
| `path <name>` (alias `dir`)     | Print the absolute profile dir. | ✅ |
| `current` (alias `whoami`)      | Print which profile the current shell is using. | ⚠️ Misleading from inside the assistant — use `list` instead |
| `remove <name>` (alias `rm`)    | Delete the profile dir. Asks y/N confirmation. Auto re-wires shortcuts on success. | ⚠️ Confirm in chat first; the y/N prompt may not render well |
| `wire` (alias `setup-shortcuts`) | (Re)generate `claude_<name>` shortcut commands for every profile **and activate them**. POSIX writes shell functions to `~/.claude-profiles/.shell-init.sh` and appends a source line to `~/.bashrc` / `~/.zshrc`; Windows writes `.cmd` files to `~/.claude-profiles/bin/` and appends that dir to the User PATH (via the registry, not `setx`). Idempotent. Auto-called by `add` and `remove`. After running, user needs to open a new terminal. | ✅ — but mutates user's rc files / User PATH |

## Inputs

| Var | Default | Purpose |
| --- | --- | --- |
| `CLAUDE_PROFILES_DIR` | `$HOME/.claude-profiles` (POSIX) / `%USERPROFILE%\.claude-profiles` (Windows) | Where profile dirs live. |
| `SHELL` (POSIX only)  | falls back to `bash`                                                              | Which shell `use` should drop you into. |

---

## Detailed usage walkthrough

### First-time setup (two accounts)

```bash
# 1. Register the two profiles in one shot.
~/.claude/skills/claude-profile-switcher/claude_profile.sh add personal
~/.claude/skills/claude-profile-switcher/claude_profile.sh add work

# 2. Authenticate the first one. Run this in YOUR terminal (not in the AI chat):
~/.claude/skills/claude-profile-switcher/claude_profile.sh login personal
#   → claude launches
#   → type /login
#   → browser opens. Sign in to your PERSONAL Claude.ai account
#   → "Logged in" message
#   → /exit

# 3. Switch your browser to the OTHER account before the next login:
#    EITHER  log out of Claude.ai
#    OR      open a different Chrome profile / Firefox container
#    OR      complete the next OAuth URL in an incognito window

# 4. Authenticate the second profile:
~/.claude/skills/claude-profile-switcher/claude_profile.sh login work
#   → /login → sign in as WORK account → /exit

# 5. Sanity check:
~/.claude/skills/claude-profile-switcher/claude_profile.sh list
#   → personal
#   → work
```

### Daily usage — running both accounts in parallel

Open **two terminals**.

**Terminal A** (your personal Claude session):
```bash
~/.claude/skills/claude-profile-switcher/claude_profile.sh use personal
# you're now in a subshell where CLAUDE_CONFIG_DIR points at personal/
claude
# this `claude` is logged in as your personal account.
# everything (sessions, conversation history, settings) stays under ~/.claude-profiles/personal/.
# when you're done: type `exit` to leave the subshell.
```

**Terminal B** (your work Claude session, running at the same time):
```bash
~/.claude/skills/claude-profile-switcher/claude_profile.sh use work
claude
# fully isolated from Terminal A. Different OAuth tokens, different session history.
```

### One-shot invocation (no subshell)

If you want to fire `claude` once with a profile and exit when done:

```bash
~/.claude/skills/claude-profile-switcher/claude_profile.sh run work
# equivalent to: CLAUDE_CONFIG_DIR=~/.claude-profiles/work claude
```

You can also pass arguments through:

```bash
~/.claude/skills/claude-profile-switcher/claude_profile.sh run work --help
```

### Inspecting what you have

```bash
# What profiles exist?
~/.claude/skills/claude-profile-switcher/claude_profile.sh list

# Where is the 'work' profile stored?
~/.claude/skills/claude-profile-switcher/claude_profile.sh path work
# → /home/you/.claude-profiles/work

# What profile is the current shell using?
~/.claude/skills/claude-profile-switcher/claude_profile.sh current
# → personal  (~/.claude-profiles/personal)
# OR
# → (no profile — CLAUDE_CONFIG_DIR is unset; using default ~/.claude)
```

### Per-profile shortcut commands (`wire`)

Running the switcher with a long path is awkward — `wire` generates one shortcut per profile so you can type `claude_<profile>` directly. **`wire` also activates the shortcuts for you**: it edits `~/.bashrc` / `~/.zshrc` (idempotent) on POSIX, and appends the bin dir to your User PATH (via the registry, not `setx`) on Windows.

```bash
# (Re)wire all shortcuts. Idempotent. add/remove call this for you.
~/.claude/skills/claude-profile-switcher/claude_profile.sh wire
#   claude_personal      →  /home/you/.claude-profiles/personal
#   claude_liem_epost    →  /home/you/.claude-profiles/liem-epost
#
# Wrote 2 shortcut(s) to ~/.claude-profiles/.shell-init.sh
#
# Activating in shell rc files:
#   appended activation to: /home/you/.bashrc
#   already activated in:   /home/you/.zshrc
#
# Open a NEW terminal to use the shortcuts.
```

After opening a new terminal:

```bash
claude_personal              # = claude under personal profile
claude_liem_epost --version  # args pass through
```

The shortcut does NOT replace your shell (unlike `use`) — when claude exits, you stay where you were.

**Sanitization:** profile name → shortcut name replaces non-alphanumeric chars with `_`, so `liem-epost` → `claude_liem_epost`.

**What wire writes to:**
- POSIX: `~/.claude-profiles/.shell-init.sh` (the function definitions, regenerated each run) **plus** one `source` line in `~/.bashrc` and `~/.zshrc` if they exist (appended once, marked with a `# claude-profile-switcher: …` comment).
- Windows: `~/.claude-profiles/bin/claude_<name>.cmd` (one per profile, regenerated each run) **plus** one entry in your **User** Path environment variable (registry-level, no truncation risk).

To undo: delete the marker block from the rc file(s) on POSIX, or remove the bin dir from User PATH via System Properties on Windows. Then `rm -rf ~/.claude-profiles/.shell-init.sh ~/.claude-profiles/bin/`.

### Cleanup

```bash
# Delete a profile and its credentials. Asks y/N first.
~/.claude/skills/claude-profile-switcher/claude_profile.sh remove old-account
```

---

## Caveats

- **macOS**: Claude Code stores credentials in the Keychain rather than the file, so per-dir isolation breaks down. This skill is **Linux + Windows** only.
- Each profile counts as a separate Claude Code login on Anthropic's side. Make sure you're not violating subscription terms by running them in parallel.
- `CLAUDE_CONFIG_DIR` is undocumented — pin a working Claude Code version if your workflow depends on this.
- `add` is idempotent (re-running is safe), but `login` will replace your current process with `claude` — only run it in a terminal you don't mind giving up.
