"""Benchmark regex cavemanize vs spaCy cavemanize on the same input.

Prints a side-by-side report: tokens, chars, % saved, time, fact preservation.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from cavemanize import cavemanize as cavemanize_regex
from cavemanize_nlp import cavemanize_nlp
from compress import count_tokens
from protect import protect, restore


def run(label: str, src: str, fn):
    protected, placeholders = protect(src)
    t0 = time.perf_counter()
    cavemanized = fn(protected)
    elapsed = time.perf_counter() - t0
    final, missing = restore(cavemanized, placeholders)
    return {
        "label": label,
        "tokens_in": count_tokens(src),
        "tokens_out": count_tokens(final),
        "chars_in": len(src),
        "chars_out": len(final),
        "elapsed_s": round(elapsed, 3),
        "placeholders_lost": len(missing),
        "pct_saved": round(100 * (1 - count_tokens(final) / max(1, count_tokens(src))), 1),
        "preview": final[:400],
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="in_", required=True)
    args = ap.parse_args()

    src = Path(args.in_).read_text(encoding="utf-8")

    results = [
        run("regex", src, cavemanize_regex),
        run("spacy", src, lambda t: cavemanize_nlp(t, abbreviate=False)),
        run("spacy+jargon", src, lambda t: cavemanize_nlp(t, abbreviate=True)),
    ]

    summary = {r["label"]: {k: v for k, v in r.items() if k != "preview"} for r in results}
    print(json.dumps(summary, indent=2, ensure_ascii=False))
    print()
    for r in results:
        print(f"--- {r['label']} preview ---")
        print(r["preview"])
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
