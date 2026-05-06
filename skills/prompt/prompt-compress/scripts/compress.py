"""Input-mode validator: confirms a Claude-rewritten file preserves every
protected span (code blocks, inline code, URLs, paths, numbers, <!-- preserve -->
blocks) from the original, and reports token savings.

Claude does the actual rewrite per the 9-rule SPEC inlined in SKILL.md; this
script is the structural fact-preservation check. Prose-level fact checking
(named entities, technical terms, word-form dates) is Claude's job in the next
SKILL.md step.
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from protect import split_segments  # noqa: E402


def count_tokens(text: str) -> int:
    """Approximate token count using o200k_base (GPT-4o tokenizer, close to Claude's)."""
    try:
        import tiktoken
        return len(tiktoken.get_encoding("o200k_base").encode(text))
    except Exception:
        return len(text) // 4


def extract_protected(text: str) -> list[str]:
    return [chunk for chunk, is_protected in split_segments(text) if is_protected]


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Validate a Claude-rewritten file preserves all protected spans "
                    "from the original, and report token savings.",
    )
    ap.add_argument("--orig", required=True, help="Original (pre-rewrite) file")
    ap.add_argument("--rewritten", required=True, help="Claude-rewritten file")
    ap.add_argument("--out", required=True, help="Where to write the validated final file")
    args = ap.parse_args()

    orig = Path(args.orig).read_text(encoding="utf-8")
    rewritten = Path(args.rewritten).read_text(encoding="utf-8")

    orig_protected = Counter(extract_protected(orig))
    rewritten_protected = Counter(extract_protected(rewritten))

    missing: list[str] = []
    for span, n in orig_protected.items():
        if rewritten_protected[span] < n:
            missing.append(span)

    report = {
        "tokens_in": count_tokens(orig),
        "tokens_out": count_tokens(rewritten),
        "chars_in": len(orig),
        "chars_out": len(rewritten),
        "protected_in_orig": sum(orig_protected.values()),
        "protected_in_rewritten": sum(rewritten_protected.values()),
        "protected_missing": missing,
    }
    report["pct_saved"] = round(
        100 * (1 - report["tokens_out"] / max(1, report["tokens_in"])), 1
    )

    if missing:
        sys.stderr.write(
            f"FAIL: {len(missing)} protected span(s) missing from rewrite:\n"
        )
        for span in missing[:5]:
            sys.stderr.write(f"  - {span!r}\n")
        if len(missing) > 5:
            sys.stderr.write(f"  ... and {len(missing) - 5} more\n")
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return 2

    Path(args.out).write_text(rewritten, encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
