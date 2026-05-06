"""Output mode: caveman simplification of an English AI response.

Default engine is spaCy: POS-aware token drops (drops auxiliaries via dep_ tag,
articles via DET POS, intensifiers via lemma+POS) plus a verified-jargon dict
(only entries that strictly save tokens under o200k_base) plus the same regex
phrasal stripping as the regex engine.

Use --engine regex to fall back to the pure-regex path (1ms vs 2-3s startup,
~half the savings on tech prose, similar on chat-style).

Code blocks, inline code, URLs, paths, and numbers are protected via sentinels
so neither engine can chew them up.

Earlier versions detected Chinese input and reverse-translated via opus-mt-zh-en;
the MT hallucinated proper nouns ("Slack" -> "Shrek") and mangled URLs, so the
ZH branch was removed. English only now.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from cavemanize import cavemanize as cavemanize_regex
from compress import count_tokens
from protect import protect, restore


def _get_engine(name: str):
    if name == "regex":
        return cavemanize_regex
    from cavemanize_nlp import cavemanize_nlp
    return lambda t: cavemanize_nlp(t, abbreviate=True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="in_", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument(
        "--engine",
        choices=["spacy", "regex"],
        default="spacy",
        help="spacy (default): POS-aware + verified jargon, ~2-3s startup. "
             "regex: fast (~1ms), ~half the savings on tech prose.",
    )
    args = ap.parse_args()

    src = Path(args.in_).read_text(encoding="utf-8")

    engine = _get_engine(args.engine)
    protected, placeholders = protect(src)
    cavemanized = engine(protected)
    final, missing = restore(cavemanized, placeholders)

    report = {
        "engine": args.engine,
        "tokens_in": count_tokens(src),
        "tokens_out": count_tokens(final),
        "chars_in": len(src),
        "chars_out": len(final),
        "placeholders_protected": len(placeholders),
        "placeholders_lost": len(missing),
        "lost_indices": missing,
    }
    report["pct_saved"] = round(
        100 * (1 - report["tokens_out"] / max(1, report["tokens_in"])), 1
    )

    if missing:
        sys.stderr.write(
            f"FAIL: {len(missing)} placeholder(s) lost: indices {missing}\n"
        )
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return 2

    Path(args.out).write_text(final, encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
