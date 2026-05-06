"""Protect content that must survive translation: code, URLs, paths, numbers, explicit preserves.

Sentinel format: ` XPHX{LABEL}XPHX ` where LABEL is exactly 4 DISTINCT uppercase letters
(A-Z, no repeats). Marian's SentencePiece tokenizer aggressively collapses runs of
identical characters in unfamiliar tokens (`AAAB` becomes `AAB`, `XPHXAAADXPHX` even
loses its trailing `XPHX`). Letters that never repeat avoid this entirely. The encoding
is base 26-25-24-23 with each position drawing from the letters NOT yet used:
358,800 unique indices, more than enough for any single document.
"""
from __future__ import annotations

import re

PATTERNS: list[str] = [
    r"<!--\s*preserve\s*-->[\s\S]*?<!--\s*/preserve\s*-->",
    r"```[\s\S]*?```",
    r"`[^`\n]+`",
    # URLs: non-greedy, stop before trailing sentence punctuation. The lookahead
    # allows 0+ trailing `.,;:!?)]>` to be excluded if followed by whitespace or
    # end of string — so `https://x.com/p.` is split as `https://x.com/p` + `.`,
    # but `https://x.com/page.html` keeps the `.html` because it's not followed
    # by whitespace.
    r"https?://\S+?(?=[.,;:!?)\]>\"']*(?:\s|$))",
    r"(?:[A-Za-z]:)?[/\\][\w./\\-]+",
    r"\b\d+(?:\.\d+)?(?:[a-zA-Z%]+)?\b",
]
COMBINED = re.compile("|".join(f"(?:{p})" for p in PATTERNS))
SENTINEL_RE = re.compile(r"XPHX([A-Z]{4})XPHX")
_MAX_INDEX = 26 * 25 * 24 * 23  # 358,800


def _idx_to_label(i: int) -> str:
    if i < 0 or i >= _MAX_INDEX:
        raise ValueError(f"placeholder index {i} out of range (0..{_MAX_INDEX - 1})")
    available = list(range(26))
    chars: list[str] = []
    for base in (26, 25, 24, 23):
        d = i % base
        i //= base
        chars.append(chr(ord("A") + available.pop(d)))
    return "".join(chars)


def _label_to_idx(label: str) -> int:
    if len(set(label)) != 4:
        return -1  # not all distinct → not a valid sentinel
    available = list(range(26))
    n = 0
    multiplier = 1
    for c in label:
        idx = ord(c) - ord("A")
        try:
            pos = available.index(idx)
        except ValueError:
            return -1
        n += pos * multiplier
        multiplier *= len(available)
        available.pop(pos)
    return n


def protect(text: str) -> tuple[str, list[str]]:
    placeholders: list[str] = []

    def sub(m: re.Match) -> str:
        placeholders.append(m.group(0))
        return f" XPHX{_idx_to_label(len(placeholders) - 1)}XPHX "

    return COMBINED.sub(sub, text), placeholders


def restore(text: str, placeholders: list[str]) -> tuple[str, list[int]]:
    """Restore placeholders. Returns (restored_text, missing_indices)."""
    seen: set[int] = set()

    def unsub(m: re.Match) -> str:
        idx = _label_to_idx(m.group(1))
        if 0 <= idx < len(placeholders):
            seen.add(idx)
            return placeholders[idx]
        return m.group(0)

    restored = SENTINEL_RE.sub(unsub, text)
    missing = [i for i in range(len(placeholders)) if i not in seen]
    return restored, missing


def split_segments(text: str) -> list[tuple[str, bool]]:
    """Split text into [(chunk, is_protected), ...] alternating segments.

    Used by input mode (compress.py) to do fragment-translation: prose chunks go
    through Marian, protected chunks bypass MT entirely. No sentinels involved,
    so no risk of the model mangling them. The protect/restore pair above is
    still used by output mode where sentinels only need to survive regex passes.
    """
    segments: list[tuple[str, bool]] = []
    last_end = 0
    for m in COMBINED.finditer(text):
        if m.start() > last_end:
            segments.append((text[last_end:m.start()], False))
        segments.append((m.group(0), True))
        last_end = m.end()
    if last_end < len(text):
        segments.append((text[last_end:], False))
    return segments
