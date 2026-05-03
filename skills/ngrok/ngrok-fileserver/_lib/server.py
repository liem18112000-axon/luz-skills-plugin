#!/usr/bin/env python3
"""
ngrok-fileserver / server.py
Lightweight directory file-server with markdown -> HTML rendering.

Stdlib + optional `markdown` package (graceful fallback to <pre>).
- Images, PDFs, videos: served raw, browser handles preview.
- *.md / *.markdown: rendered to HTML.
- Other text-like (.txt, .log, .json, .yml, .yaml): forced inline so the
  browser shows them instead of triggering a download.

Usage:
  python server.py <root-dir>            # PORT=8765 default
  PORT=9000 python server.py <root-dir>
"""
import http.server
import socketserver
import datetime
import fnmatch
import os
import signal
import sys
import html
import secrets
import threading
import time
import mimetypes
import urllib.parse
from http.cookies import SimpleCookie
from pathlib import Path

HTTPD = None  # populated by main() so handlers can call HTTPD.shutdown()

try:
    import markdown as md_lib
    HAVE_MD = True
except ImportError:
    HAVE_MD = False

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
PORT = int(os.environ.get("PORT", "8765"))
BIND = os.environ.get("BIND", "127.0.0.1")
PASSCODE = os.environ.get("PASSCODE", "18112000")
SESSION_TOKEN = secrets.token_urlsafe(24)
COOKIE_NAME = "ngfs_auth"

INLINE_TEXT_EXTS = {".txt", ".log", ".json", ".yml", ".yaml", ".csv", ".sh", ".cmd", ".py", ".js", ".ts"}
MD_EXTS = {".md", ".markdown"}

# Defense-in-depth: refuse to serve anything matching these globs at any path
# component. Override via DENY_GLOBS env var (comma-separated). Set DENY_GLOBS=""
# to disable (NOT recommended when ROOT is $HOME or wider).
_DEFAULT_DENY_GLOBS = [
    # SSH / TLS / cloud auth dirs (all common cloud CLIs, both bare and under .config/)
    ".ssh", ".kube", ".docker", ".aws", ".gcloud", ".gnupg", ".password-store",
    "gcloud", "aws", "gh", "doctl", "azure", "fly", "heroku",
    # AI tool credentials
    ".codex", ".copilot", ".gemini", ".kimi", ".ollama", ".claude*",
    # package manager / VCS auth & local caches that hold OAuth tokens
    ".npmrc", ".pypirc", ".git-credentials", ".gitconfig", ".netrc",
    ".gradle", ".m2", ".nuget", ".cargo", ".sbt", ".ivy2",
    # Windows app-data trove + reparse-point junctions that loop back to it
    "AppData", "Cookies", "Application Data", "Local Settings", "My Documents",
    "NetHood", "PrintHood", "Recent", "SendTo", "Start Menu", "Templates",
    # env / secrets files
    ".env*",
    # private keys & certs
    "*.pem", "*.key", "*.p12", "*.pfx", "*.crt", "*.ovpn",
    "id_rsa*", "id_ed25519*", "id_ecdsa*", "id_dsa*",
    # generic credentials patterns
    "*credentials*", "*credential.*",
    # ngrok config
    "ngrok.yml",
    # shell history (often contains secrets in command lines)
    ".bash_history", ".zsh_history", ".python_history", ".mysql_history", ".psql_history",
]
_env_deny = os.environ.get("DENY_GLOBS")
if _env_deny is None:
    DENY_GLOBS = list(_DEFAULT_DENY_GLOBS)
else:
    DENY_GLOBS = [g.strip() for g in _env_deny.split(",") if g.strip()]


def _component_denied(name):
    n = name.lower()
    for glob in DENY_GLOBS:
        if fnmatch.fnmatch(name, glob) or fnmatch.fnmatch(n, glob.lower()):
            return True
    return False


def _path_denied(fs_path):
    try:
        rel = fs_path.relative_to(ROOT)
    except ValueError:
        return True
    for part in rel.parts:
        if _component_denied(part):
            return True
    return False


_ICON_MAP = {
    ".md": ("📝", "Markdown"), ".markdown": ("📝", "Markdown"),
    ".py": ("🐍", "Python"), ".js": ("📜", "JavaScript"), ".ts": ("📜", "TypeScript"),
    ".sh": ("⚙", "Shell script"), ".cmd": ("⚙", "Batch script"), ".bat": ("⚙", "Batch script"), ".ps1": ("⚙", "PowerShell"),
    ".json": ("📋", "JSON"), ".yml": ("📋", "YAML"), ".yaml": ("📋", "YAML"), ".toml": ("📋", "TOML"), ".xml": ("📋", "XML"),
    ".csv": ("📊", "CSV"), ".log": ("📋", "Log"), ".txt": ("📄", "Text"),
    ".pdf": ("📕", "PDF"),
    ".png": ("🖼", "Image"), ".jpg": ("🖼", "Image"), ".jpeg": ("🖼", "Image"),
    ".gif": ("🖼", "Image"), ".webp": ("🖼", "Image"), ".svg": ("🖼", "Image"), ".ico": ("🖼", "Icon"),
    ".mp4": ("🎬", "Video"), ".webm": ("🎬", "Video"), ".mov": ("🎬", "Video"), ".mkv": ("🎬", "Video"),
    ".mp3": ("🎵", "Audio"), ".wav": ("🎵", "Audio"), ".flac": ("🎵", "Audio"),
    ".zip": ("🗜", "Archive"), ".tar": ("🗜", "Archive"), ".gz": ("🗜", "Archive"),
    ".7z": ("🗜", "Archive"), ".rar": ("🗜", "Archive"),
    ".html": ("🌐", "HTML"), ".htm": ("🌐", "HTML"), ".css": ("🎨", "CSS"),
    ".java": ("☕", "Java"), ".kt": ("☕", "Kotlin"), ".scala": ("☕", "Scala"),
    ".go": ("🐹", "Go"), ".rs": ("🦀", "Rust"), ".rb": ("💎", "Ruby"),
    ".c": ("📘", "C"), ".cpp": ("📘", "C++"), ".h": ("📘", "Header"), ".hpp": ("📘", "Header"),
    ".sql": ("🗃", "SQL"), ".db": ("🗃", "Database"),
    ".lock": ("🔒", "Lock file"),
}


def _entry_icon_and_type(name, is_dir):
    if is_dir:
        return ("📁", "Folder")
    ext = Path(name).suffix.lower()
    if ext in _ICON_MAP:
        return _ICON_MAP[ext]
    if ext:
        return ("📄", ext[1:].upper() + " file")
    return ("📄", "File")


def _human_size(n):
    if n < 1024:
        return f"{n:,} B"
    f = float(n)
    for unit in ("KB", "MB", "GB", "TB"):
        f /= 1024
        if f < 1024:
            return f"{f:,.1f} {unit}"
    return f"{f:,.1f} PB"


def _human_date(ts):
    try:
        dt = datetime.datetime.fromtimestamp(ts)
    except (OSError, ValueError, OverflowError):
        return ""
    now = datetime.datetime.now()
    today = now.date()
    if dt.date() == today:
        return "Today " + dt.strftime("%H:%M")
    if (today - dt.date()).days == 1:
        return "Yesterday " + dt.strftime("%H:%M")
    if dt.year == now.year:
        return dt.strftime("%b %d, %H:%M")
    return dt.strftime("%Y-%m-%d")

CSS = """
:root { color-scheme: light; }
body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Segoe UI Variable", sans-serif;
       max-width: 1100px; margin: 1.5em auto; padding: 0 1em; line-height: 1.5; color: #1a1a1a; background: #fafafa; }
h2 { margin: 0 0 0.6em 0; font-weight: 500; font-size: 1.25em; color: #222; }
pre, code { background: #f4f4f4; border-radius: 4px; }
code { padding: 0.15em 0.35em; font-size: 0.95em; }
pre { padding: 0.9em 1em; overflow-x: auto; font-size: 0.92em; }
pre code { padding: 0; background: transparent; }
img { max-width: 100%; height: auto; }
hr { border: 0; border-top: 1px solid #ddd; margin: 2em 0; }

/* breadcrumb / address bar */
.crumbs { display: flex; align-items: center; gap: 0.3em; flex-wrap: wrap;
          padding: 0.55em 0.9em; margin-bottom: 0.7em;
          background: #fff; border: 1px solid #d6d6d6; border-radius: 6px;
          font-size: 0.93em; }
.crumbs a { color: #0067c0; text-decoration: none; padding: 0.15em 0.45em; border-radius: 3px; }
.crumbs a:hover { background: #eaf4ff; text-decoration: underline; }
.crumbs .sep { color: #999; }
.crumbs .here { color: #555; padding: 0.15em 0.45em; }

/* path search */
.gobar { display: flex; gap: 0.5em; margin-bottom: 1em; }
.gobar input { flex: 1; padding: 0.5em 0.75em; font-size: 0.95em;
               border: 1px solid #c8c8c8; border-radius: 6px; background: #fff;
               font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
.gobar input:focus { outline: none; border-color: #0067c0; box-shadow: 0 0 0 2px rgba(0,103,192,0.18); }
.gobar button { padding: 0.5em 1.1em; font-size: 0.95em; cursor: pointer;
                background: #0067c0; color: #fff; border: 0; border-radius: 6px; font-weight: 500; }
.gobar button:hover { background: #0058a8; }
.gobar .err { color: #b80000; padding: 0.4em 0; font-size: 0.9em; }

/* explorer table */
table.explorer { width: 100%; border-collapse: collapse; background: #fff;
                 border: 1px solid #d6d6d6; border-radius: 6px; overflow: hidden; font-size: 0.92em; }
table.explorer thead th { text-align: left; padding: 0.55em 0.85em; font-weight: 500;
                          color: #444; background: #f3f3f3; border-bottom: 1px solid #d6d6d6; user-select: none; }
table.explorer th.right, table.explorer td.right { text-align: right; }
table.explorer th.icon, table.explorer td.icon { width: 1.6em; text-align: center; padding-right: 0.2em; padding-left: 0.6em; }
table.explorer tbody tr { border-bottom: 1px solid #efefef; }
table.explorer tbody tr:last-child { border-bottom: 0; }
table.explorer tbody tr:hover { background: #eaf4ff; }
table.explorer td { padding: 0.42em 0.85em; }
table.explorer td.icon { font-size: 1.05em; }
table.explorer td.size { color: #444; font-variant-numeric: tabular-nums; white-space: nowrap; }
table.explorer td.type { color: #666; white-space: nowrap; }
table.explorer td.modified { color: #666; white-space: nowrap; font-variant-numeric: tabular-nums; }
table.explorer a { color: #0a0a0a; text-decoration: none; }
table.explorer a:hover { text-decoration: underline; color: #0067c0; }
.empty { padding: 1.5em; text-align: center; color: #888; }
.summary { color: #666; font-size: 0.85em; padding: 0.4em 0; }

/* shutdown button */
.toolbar { display: flex; align-items: center; gap: 0.6em; margin-bottom: 0.7em; }
.toolbar .crumbs { flex: 1; margin-bottom: 0; }
.toolbar form { margin: 0; }
.shutdown-btn { padding: 0.5em 1em; background: #fff; color: #b80000; border: 1px solid #d8a8a8;
                border-radius: 6px; cursor: pointer; font-size: 0.88em; font-weight: 500; white-space: nowrap; }
.shutdown-btn:hover { background: #b80000; color: #fff; border-color: #b80000; }
.stopped { padding: 2em; text-align: center; }
.stopped h2 { color: #b80000; }
"""


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def log_message(self, fmt, *args):
        sys.stderr.write("[server] " + (fmt % args) + "\n")

    def _is_authed(self):
        cookie = SimpleCookie(self.headers.get("Cookie", ""))
        morsel = cookie.get(COOKIE_NAME)
        return morsel is not None and secrets.compare_digest(morsel.value, SESSION_TOKEN)

    def _login_form(self, error=False):
        msg = "<p style='color:#c00'>Wrong passcode.</p>" if error else ""
        body = (
            "<form method='POST' action='/__login' style='display:flex;flex-direction:column;gap:0.8em;max-width:280px;margin:4em auto;'>"
            "<label>Enter passcode</label>"
            "<input type='password' name='passcode' autofocus required "
            "style='padding:0.6em;font-size:1.1em;border:1px solid #ccc;border-radius:4px;'>"
            "<button type='submit' style='padding:0.6em;font-size:1em;background:#222;color:#fff;border:0;border-radius:4px;cursor:pointer;'>Unlock</button>"
            f"{msg}"
            "</form>"
        )
        return self._wrap("Locked", body)

    def _send_login(self, status=401, error=False):
        page = self._login_form(error=error).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(page)))
        self.end_headers()
        self.wfile.write(page)

    def do_POST(self):
        if self.path == "/__login":
            length = int(self.headers.get("Content-Length", "0") or "0")
            raw = self.rfile.read(length).decode("utf-8", errors="replace")
            fields = urllib.parse.parse_qs(raw)
            submitted = (fields.get("passcode") or [""])[0]
            if secrets.compare_digest(submitted, PASSCODE):
                self.send_response(303)
                self.send_header("Location", "/")
                self.send_header("Set-Cookie", f"{COOKIE_NAME}={SESSION_TOKEN}; Path=/; HttpOnly; SameSite=Lax")
                self.send_header("Content-Length", "0")
                self.end_headers()
                sys.stderr.write("[server] login OK\n")
            else:
                sys.stderr.write("[server] login FAILED\n")
                self._send_login(status=401, error=True)
            return

        if self.path == "/__shutdown":
            if not self._is_authed():
                return self._send_login()
            length = int(self.headers.get("Content-Length", "0") or "0")
            if length:
                self.rfile.read(length)
            body = self._wrap(
                "Stopped",
                '<div class="stopped">'
                '<h2>🛑 Server stopped</h2>'
                '<p>The local file server has been shut down. The ngrok tunnel will return 502 to any new requests.</p>'
                '<p>To restart: re-run <code>serve.sh</code> / <code>serve.cmd</code> on your machine.</p>'
                '</div>'
            ).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(body)
            try:
                self.wfile.flush()
            except OSError:
                pass
            sys.stderr.write("[server] /__shutdown received — stopping\n")

            def _do_shutdown():
                # Give the response a moment to finish flushing.
                time.sleep(0.4)
                # Try to signal the parent (serve.sh wrapper) so it kills ngrok via its trap.
                try:
                    ppid = os.getppid()
                    if ppid and ppid != 1:
                        os.kill(ppid, signal.SIGTERM)
                except Exception:
                    pass
                # Stop the HTTP server itself.
                if HTTPD is not None:
                    try:
                        HTTPD.shutdown()
                    except Exception:
                        pass
                # Belt-and-braces: hard exit if shutdown didn't unblock serve_forever in time.
                time.sleep(2.0)
                os._exit(0)

            threading.Thread(target=_do_shutdown, daemon=True).start()
            return

        self.send_error(404, "not found")

    def do_GET(self):
        if not self._is_authed():
            return self._send_login()
        path_only, _, qs = self.path.partition("?")
        # /__goto?path=… — resolve and 302 to the path if it exists, else show listing with error.
        if path_only == "/__goto":
            target = (urllib.parse.parse_qs(qs).get("path") or [""])[0].strip()
            target_norm = target.replace("\\", "/").lstrip("/")
            try:
                fs_path = (ROOT / target_norm).resolve()
            except (OSError, ValueError):
                fs_path = None
            if fs_path and str(fs_path).startswith(str(ROOT)) and fs_path.exists() and not _path_denied(fs_path):
                loc = "/" + urllib.parse.quote(target_norm) + ("/" if fs_path.is_dir() else "")
                self.send_response(302)
                self.send_header("Location", loc)
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            return self._send_goto_not_found(target)

        rel = urllib.parse.unquote(path_only).lstrip("/")
        fs_path = (ROOT / rel).resolve()
        if not str(fs_path).startswith(str(ROOT)):
            self.send_error(403, "forbidden")
            return
        if _path_denied(fs_path):
            self.send_error(404, "not found")
            return
        if fs_path.is_file():
            ext = fs_path.suffix.lower()
            if ext in MD_EXTS:
                return self._serve_markdown(fs_path)
            if ext in INLINE_TEXT_EXTS:
                return self._serve_inline_text(fs_path)
        return super().do_GET()

    def _send_goto_not_found(self, target):
        body = (
            f'<div class="gobar"><div class="err">Path not found or not accessible: '
            f'<code>{html.escape(target)}</code></div></div>'
            f'<p><a href="/">← back to root</a></p>'
        )
        page = self._wrap("Not found", body).encode("utf-8")
        self.send_response(404)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(page)))
        self.end_headers()
        self.wfile.write(page)

    def list_directory(self, path):
        try:
            all_entries = list(os.scandir(path))
        except OSError:
            self.send_error(404, "not found")
            return None
        entries = sorted(
            (e for e in all_entries if not _component_denied(e.name)),
            key=lambda e: (not e.is_dir(), e.name.lower()),
        )
        rel = urllib.parse.unquote(self.path.split("?", 1)[0]).rstrip("/")
        title = "📁 " + (rel or "/")

        # Breadcrumb + shutdown button (toolbar)
        crumbs = ['<a href="/">📁 root</a>']
        accum = ""
        for part in [p for p in rel.lstrip("/").split("/") if p]:
            accum += "/" + urllib.parse.quote(part)
            crumbs.append('<span class="sep">/</span>')
            crumbs.append(f'<a href="{accum}/">{html.escape(part)}</a>')
        toolbar = (
            '<div class="toolbar">'
            f'<div class="crumbs">{"".join(crumbs)}</div>'
            '<form method="POST" action="/__shutdown" '
            'onsubmit="return confirm(\'Stop the file server? The ngrok tunnel will go down.\');">'
            '<button type="submit" class="shutdown-btn" title="Stop the python server (and ngrok tunnel)">'
            '🛑 Shut down</button>'
            '</form>'
            '</div>'
        )

        # Path search bar (GETs /__goto?path=…)
        gobar = (
            '<form class="gobar" method="GET" action="/__goto" autocomplete="off">'
            '<input type="text" name="path" placeholder="Go to path  e.g.  Kepler/luz_docs/src/main/java/…" '
            'spellcheck="false" autocomplete="off">'
            '<button type="submit">Go</button>'
            '</form>'
        )

        # Build explorer table
        rows = []
        if rel:
            rows.append(
                '<tr><td class="icon">↩</td><td><a href="../">..</a></td>'
                '<td class="size"></td><td class="type">Folder</td><td class="modified"></td></tr>'
            )
        n_dirs = n_files = total_size = 0
        for e in entries:
            try:
                is_dir = e.is_dir()
            except OSError:
                is_dir = False
            icon, type_label = _entry_icon_and_type(e.name, is_dir)
            link = urllib.parse.quote(e.name) + ("/" if is_dir else "")
            display = html.escape(e.name) + ("/" if is_dir else "")
            try:
                stat = e.stat()
                if is_dir:
                    size_html = ""
                    n_dirs += 1
                else:
                    size_html = _human_size(stat.st_size)
                    n_files += 1
                    total_size += stat.st_size
                modified_html = _human_date(stat.st_mtime)
            except OSError:
                size_html = ""
                modified_html = ""
            rows.append(
                f'<tr>'
                f'<td class="icon">{icon}</td>'
                f'<td><a href="{link}">{display}</a></td>'
                f'<td class="size">{size_html}</td>'
                f'<td class="type">{type_label}</td>'
                f'<td class="modified">{modified_html}</td>'
                f'</tr>'
            )

        if not entries and not rel:
            table_body = '<tr><td colspan="5" class="empty">(empty)</td></tr>'
        else:
            table_body = "".join(rows)

        summary = (
            f'<div class="summary">{n_dirs} folder{"s" if n_dirs != 1 else ""}, '
            f'{n_files} file{"s" if n_files != 1 else ""}'
            f'{f" — {_human_size(total_size)} total" if n_files else ""}'
            f'</div>'
        )

        table = (
            '<table class="explorer">'
            '<thead><tr>'
            '<th class="icon"></th>'
            '<th>Name</th>'
            '<th class="right">Size</th>'
            '<th>Type</th>'
            '<th>Modified</th>'
            '</tr></thead>'
            f'<tbody>{table_body}</tbody>'
            '</table>'
        )

        page = self._wrap(title, toolbar + gobar + table + summary)
        self._send_html(page)
        return None

    def _serve_markdown(self, fs_path):
        text = fs_path.read_text(encoding="utf-8", errors="replace")
        if HAVE_MD:
            body = md_lib.markdown(
                text,
                extensions=["fenced_code", "tables", "toc", "sane_lists"],
            )
        else:
            body = "<p><em>(install <code>pip install markdown</code> for rendered output — showing raw)</em></p><pre>" + html.escape(text) + "</pre>"
        self._send_html(self._wrap(fs_path.name, body))

    def _serve_inline_text(self, fs_path):
        text = fs_path.read_text(encoding="utf-8", errors="replace")
        body = f"<pre>{html.escape(text)}</pre>"
        self._send_html(self._wrap(fs_path.name, body))

    def _wrap(self, title, body):
        return (
            "<!doctype html><html><head><meta charset='utf-8'>"
            f"<title>{html.escape(title)}</title><style>{CSS}</style></head>"
            f"<body><h2>{html.escape(title)}</h2>{body}</body></html>"
        )

    def _send_html(self, page):
        encoded = page.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)


def main():
    if not ROOT.exists():
        sys.stderr.write(f"[server] root does not exist: {ROOT}\n")
        sys.exit(2)
    global HTTPD
    sys.stderr.write(f"[server] serving {ROOT} on http://{BIND}:{PORT} (markdown={'on' if HAVE_MD else 'off'}, passcode={'set' if PASSCODE else 'OFF'})\n")
    sys.stderr.flush()
    with socketserver.ThreadingTCPServer((BIND, PORT), Handler) as httpd:
        httpd.allow_reuse_address = True
        HTTPD = httpd
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            sys.stderr.write("\n[server] stopped\n")
        finally:
            HTTPD = None


if __name__ == "__main__":
    main()
