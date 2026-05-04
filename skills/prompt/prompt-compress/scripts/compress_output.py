"""Output mode: detect lang → reverse-translate to EN → cavemanize → JSON report."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from cavemanize import cavemanize  # noqa: E402
from compress import count_tokens, split_sentences  # noqa: E402
from protect import protect, restore  # noqa: E402
from translate import wenyan_to_zh, zh_to_en  # noqa: E402

CLASSICAL_PARTICLES = ("之", "也", "矣", "乎", "焉", "哉", "而", "者", "其", "於")
MODERN_MARKERS = ("的", "了", "是", "在", "我们", "你们", "什么", "怎么", "这个", "那个")


def detect(text: str) -> str:
    """Return one of 'en', 'zh', 'wy'."""
    n = len(text)
    if n == 0:
        return "en"
    han = sum(1 for c in text if "一" <= c <= "鿿")
    if han / n < 0.10:
        return "en"
    classical = sum(text.count(w) for w in CLASSICAL_PARTICLES)
    modern = sum(text.count(w) for w in MODERN_MARKERS)
    return "wy" if classical >= modern else "zh"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="in_", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--force-lang", choices=["en", "zh", "wy"],
                    help="Skip detection, treat input as this language.")
    args = ap.parse_args()

    src = Path(args.in_).read_text(encoding="utf-8")
    lang = args.force_lang or detect(src)

    if lang == "wy":
        zh = "\n".join(wenyan_to_zh(s) for s in split_sentences(src))
        en = "\n".join(zh_to_en(s) for s in split_sentences(zh))
    elif lang == "zh":
        en = "\n".join(zh_to_en(s) for s in split_sentences(src))
    else:
        en = src

    protected, placeholders = protect(en)
    cavemanized = cavemanize(protected)
    final, missing = restore(cavemanized, placeholders)

    report = {
        "detected_lang": lang,
        "tokens_in": count_tokens(src),
        "tokens_after_translate": count_tokens(en),
        "tokens_out": count_tokens(final),
        "chars_in": len(src),
        "chars_out": len(final),
        "placeholders_protected": len(placeholders),
        "placeholders_lost": len(missing),
        "lost_indices": missing,
    }
    report["pct_saved_total"] = round(
        100 * (1 - report["tokens_out"] / max(1, report["tokens_in"])), 1
    )
    report["pct_saved_caveman_only"] = round(
        100 * (1 - report["tokens_out"] / max(1, report["tokens_after_translate"])), 1
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
