"""Rule-based caveman simplifier for English text.

Applies a subset of the wilpel/caveman-compression SPEC v1.0:
- Strip pure intensifiers (rule 6)
- Drop articles (rule 7)
- Drop hedges and pleasantries (out-of-spec but matches JuliusBrussee/caveman style)
- Drop sentence-level connectives (rule 3)
- Collapse whitespace

Does NOT (yet) split compound sentences (rule 1) or convert passive→active (rule 4)
— those need more than regex. This module gets ~15-30% reduction; for higher
quality use an LLM rewriter.

Always run protect.py first so code blocks, URLs, paths, numbers survive untouched.
"""
from __future__ import annotations

import re

INTENSIFIERS = re.compile(
    r"\b(?:very|extremely|quite|rather|really|somewhat|fairly|pretty|incredibly"
    r"|absolutely|totally|completely|utterly|highly)\s+",
    re.IGNORECASE,
)

HEDGES = re.compile(
    r"\b(?:I think|I believe|I feel|in my opinion|it seems(?: that)?"
    r"|it appears(?: that)?|perhaps|maybe|kind of|sort of|arguably|presumably)\b\s*,?\s*",
    re.IGNORECASE,
)

PLEASANTRIES = re.compile(
    r"\b(?:please|thanks|thank you|sure|of course|certainly|absolutely"
    r"|happy to help|glad to help|let me know|feel free)\b\s*,?\s*",
    re.IGNORECASE,
)

CONNECTIVES = re.compile(
    r"\b(?:however|therefore|moreover|furthermore|consequently|nevertheless"
    r"|in order to|as a result|in addition|on the other hand|that said"
    r"|with that being said|having said that)\b\s*,?\s*",
    re.IGNORECASE,
)

# Articles — only at word boundaries, case-insensitive. Run after the others
# so we don't strip "the" from "however the".
ARTICLES = re.compile(r"\b(?:a|an|the)\s+", re.IGNORECASE)

# Common AI-output filler clauses.
FILLER_CLAUSES = re.compile(
    r"\b(?:as an AI(?: assistant)?|as a language model|I'd be happy to"
    r"|I can help (?:you )?with that|let's (?:dive into|explore|go through))\b[^.]*\.?\s*",
    re.IGNORECASE,
)


def cavemanize(text: str) -> str:
    """Apply rule-based caveman simplification to English text.

    Caller should run protect.protect() first to swap out code/URLs/numbers.
    """
    text = FILLER_CLAUSES.sub("", text)
    text = HEDGES.sub("", text)
    text = PLEASANTRIES.sub("", text)
    text = CONNECTIVES.sub("", text)
    text = INTENSIFIERS.sub("", text)
    text = ARTICLES.sub("", text)

    # Capitalize sentence starts that lost their leading article/connective.
    text = re.sub(
        r"(^|[.!?]\s+)([a-z])",
        lambda m: m.group(1) + m.group(2).upper(),
        text,
    )

    # Collapse runs of spaces and orphan punctuation.
    text = re.sub(r"\s*,\s*,", ",", text)
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n[ \t]+", "\n", text)
    text = re.sub(r"[ \t]+\n", "\n", text)
    text = re.sub(r"\n{3,}", "\n\n", text)

    return text.strip()


if __name__ == "__main__":
    import sys
    src = sys.stdin.read()
    sys.stdout.write(cavemanize(src))
