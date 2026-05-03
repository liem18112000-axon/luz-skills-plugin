---
name: ngrok-fileserver
description: Spin up a tiny Python HTTP server with markdown rendering over a folder, then expose it publicly via ngrok. File-explorer-style directory listing; renders .md to HTML; lets the browser preview images, PDFs, videos; inlines .txt/.log/.json/.yml. Use when the user wants to "share this folder", "expose <dir> via ngrok", "give me a public URL for <folder>", "let me see the screenshots from my phone", or any equivalent. Auto-installs python + ngrok where possible; refuses to start until ngrok authtoken is configured. Cross-platform — ships a Windows .cmd and a POSIX .sh runner.
---

# ngrok-fileserver

Browse a local folder from anywhere via a public ngrok URL. Built on Python's `http.server` with a thin handler that renders markdown to HTML and inlines common text formats. Browsers preview images / PDFs / videos natively.

Foreground command — runs until you Ctrl-C. Two processes are started: `python` (local file server) and `ngrok` (the tunnel).

## Inputs

| Var            | Required? | Default |
| -------------- | --------- | ------- |
| `FOLDER`       | **yes**   | (no default — pass as 1st positional, e.g. the screenshot dir from `playwright-klara-earchive`) |
| `PORT`         | optional  | `8765`  |
| `LOCAL_ONLY`   | optional  | unset → ngrok tunnel + public URL. Set to `1` to skip ngrok and only print `http://localhost:<PORT>/` |
| `NGROK_REGION` | optional  | unset → ngrok auto. Override with `us`, `eu`, `ap`, `au`, `sa`, `jp`, `in` for lower latency |
| `PASSCODE`     | optional  | `18112000` — single-input login gate. Visitors hit `/__login` form first; correct passcode sets a session cookie (in-memory, dies with the server). Set `PASSCODE=""` to disable auth (NOT recommended on a public ngrok URL). |

## Files in this skill

```
ngrok-fileserver/
├── SKILL.md
├── bootstrap.cmd / bootstrap.sh    (verify python + ngrok, install where possible, check authtoken)
├── serve.cmd     / serve.sh        (main entry — starts python server then ngrok)
└── _lib/
    └── server.py                   (stdlib HTTP handler with .md → HTML, inline text)
```

## How to gather inputs

1. Parse `KEY=VALUE` args. Accept a bare positional path for `FOLDER`.
2. **Always** ask for `FOLDER` if missing.
3. Don't prompt for the rest — apply defaults, print the resolved tuple before running.
4. **Sensitivity check** — before serving, glance at the folder. If it contains anything that smells like secrets (`*.key`, `*.pem`, `.env`, `credentials.json`, screenshots of login pages), warn the user and ask for confirmation. ngrok URLs are anyone-with-link readable.

## How to invoke

### Step 0 — Bootstrap

```
~/.claude/skills/ngrok-fileserver/bootstrap.sh
```

Checks `python`, `ngrok`, `ngrok config check` (authtoken), and the `markdown` pip package. Installs what it can via `winget`/`brew`/`apt-get`. If exit 1, surface the printed instructions and stop. The authtoken step is one-time, interactive — sign up at <https://dashboard.ngrok.com/get-started/your-authtoken> and run `ngrok config add-authtoken <YOUR-TOKEN>`.

### Step 1 — Serve

#### POSIX (preferred):
```bash
~/.claude/skills/ngrok-fileserver/serve.sh "/abs/path/to/folder"

# Custom port
PORT=9090 ~/.claude/skills/ngrok-fileserver/serve.sh "/path"

# Local only — no public exposure
LOCAL_ONLY=1 ~/.claude/skills/ngrok-fileserver/serve.sh "/path"

# EU region
NGROK_REGION=eu ~/.claude/skills/ngrok-fileserver/serve.sh "/path"
```

#### Windows (cmd / PowerShell):
```cmd
"%USERPROFILE%\.claude\skills\ngrok-fileserver\serve.cmd" "C:\path\to\folder"

set PORT=9090
"%USERPROFILE%\.claude\skills\ngrok-fileserver\serve.cmd" "C:\path"
```

### Step 2 — Read the public URL

`serve.sh` boxes the public ngrok URL in the output as soon as ngrok establishes the tunnel:

```
[serve] ╔══ PUBLIC URL ══════════════════════════════════
[serve] ║ https://abcd-1234-56.ngrok-free.app
[serve] ╚════════════════════════════════════════════════
```

That URL is what you (or anyone you forward it to) opens in a browser.

### Step 3 — Stop

`Ctrl-C` in the foreground terminal kills both processes (the script's exit-trap reaps the python server). If you backgrounded it: `pkill ngrok && pkill -f server.py` (POSIX) or stop the python window manually (Windows .cmd doesn't auto-clean its background python — kill from Task Manager if needed).

## What the server renders

| Extension                          | Behavior                                  |
| ---------------------------------- | ----------------------------------------- |
| `.md`, `.markdown`                 | Rendered to HTML (`pip install markdown`) |
| `.txt`, `.log`, `.json`, `.yml`, `.yaml`, `.csv`, `.sh`, `.cmd`, `.py`, `.js`, `.ts` | Inline `<pre>` (forces preview, not download) |
| `.png`, `.jpg`, `.gif`, `.webp`, `.svg` | Browser native preview |
| `.pdf`                             | Browser native preview                    |
| `.mp4`, `.webm`, `.mov`            | Browser native player                     |
| Anything else                      | Standard HTTP file response (browser decides) |

## Pairs well with

- `playwright-klara-earchive` (screenshots dir → share so a colleague can see them on their phone)
- Any local report/dashboard you generated that you want to share without uploading to a third-party host

## Caveats

- **Public exposure.** Anyone with the URL can read every file in the folder for as long as the tunnel is up. Don't serve `~`, `/`, `$HOME`, or anything containing secrets.
- **Free-tier ngrok URLs are session-scoped** — the URL changes every restart. For a stable URL, ngrok paid plans + reserved domains. Out of scope for this skill.
- **Not for big files / many users.** This is a one-listener Python server; not optimised for bandwidth or concurrency. Fine for "let me show you these screenshots" — not fine for a download mirror.
- **Windows .cmd doesn't reap the python child cleanly on Ctrl-C** — if you exit and `localhost:8765` is still answering, kill the leftover python from Task Manager. The .sh runner does reap correctly.
- **Markdown is rendered server-side via `python -m markdown`.** The skill's bootstrap installs the package via `pip --user`. If pip isn't available the server falls back to a plain `<pre>` with the raw markdown.
