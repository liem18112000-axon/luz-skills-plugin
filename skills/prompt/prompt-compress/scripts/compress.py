"""protect → en→zh → zh→wenyan → restore → JSON report."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from protect import protect, restore  # noqa: E402
from translate import en_to_zh, zh_to_wenyan  # noqa: E402


def split_sentences(text: str) -> list[str]:
    out: list[str] = []
    buf: list[str] = []
    for ch in text:
        buf.append(ch)
        if ch in ".!?。！？\n":
            chunk = "".join(buf).strip()
            if chunk:
                out.append(chunk)
            buf = []
    tail = "".join(buf).strip()
    if tail:
        out.append(tail)
    return out


def count_tokens(text: str) -> int:
    try:
        import tiktoken
        return len(tiktoken.get_encoding("cl100k_base").encode(text))
    except Exception:
        cjk = sum(1 for c in text if "一" <= c <= "鿿")
        return cjk + (len(text) - cjk) // 4


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="in_", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    src = Path(args.in_).read_text(encoding="utf-8")

    protected, placeholders = protect(src)

    zh_chunks = [en_to_zh(s) for s in split_sentences(protected)]
    zh = "\n".join(zh_chunks)

    wy_chunks = [zh_to_wenyan(s) for s in split_sentences(zh)]
    wy = "\n".join(wy_chunks)

    final, missing = restore(wy, placeholders)

    report = {
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
            f"FAIL: {len(missing)} placeholder(s) lost in translation: indices {missing}\n"
        )
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return 2

    Path(args.out).write_text(final, encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
