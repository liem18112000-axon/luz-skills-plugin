"""Protect content that must survive translation: code, URLs, paths, numbers, explicit preserves."""
from __future__ import annotations

import re

PATTERNS: list[str] = [
    r"<!--\s*preserve\s*-->[\s\S]*?<!--\s*/preserve\s*-->",
    r"```[\s\S]*?```",
    r"`[^`\n]+`",
    r"https?://\S+",
    r"(?:[A-Za-z]:)?[/\\][\w./\\-]+",
    r"\b\d+(?:\.\d+)?(?:[a-zA-Z%]+)?\b",
]
COMBINED = re.compile("|".join(f"(?:{p})" for p in PATTERNS))
SENTINEL_RE = re.compile(r"XPHX(\d{4})XPHX")


def protect(text: str) -> tuple[str, list[str]]:
    placeholders: list[str] = []

    def sub(m: re.Match) -> str:
        placeholders.append(m.group(0))
        return f" XPHX{len(placeholders) - 1:04d}XPHX "

    return COMBINED.sub(sub, text), placeholders


def restore(text: str, placeholders: list[str]) -> tuple[str, list[int]]:
    """Restore placeholders. Returns (restored_text, missing_indices)."""
    seen: set[int] = set()

    def unsub(m: re.Match) -> str:
        idx = int(m.group(1))
        if 0 <= idx < len(placeholders):
            seen.add(idx)
            return placeholders[idx]
        return m.group(0)

    restored = SENTINEL_RE.sub(unsub, text)
    missing = [i for i in range(len(placeholders)) if i not in seen]
    return restored, missing
