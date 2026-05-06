"""spaCy-based caveman simplifier — sibling to cavemanize.py.

Drop-in replacement that uses POS tags + dependency parses to make smarter
decisions than the regex-only version:

- Articles (DET tagged a/an/the) → dropped, same as regex.
- Auxiliary verbs (dep_ in {aux, auxpass}) → dropped. Distinguishes "is running"
  (aux, drop) from "is critical" (cop / ROOT, keep). Regex can't.
- Pure intensifier adverbs (POS == ADV with lemma in intensifier set) → dropped.
  Regex would also strip non-intensifier adverbs that share spelling.
- Phrasal filler (hedges, pleasantries, connectives, AI-clauses) → handled by
  the same regex layer as cavemanize.py, since these patterns span multiple
  tokens and don't map cleanly to a single POS tag.

Run protect.protect() FIRST so code blocks, URLs, paths, numbers don't get
tokenized by spaCy.
"""
from __future__ import annotations

import re
from functools import lru_cache

INTENSIFIER_LEMMAS = {
    "very", "extremely", "quite", "rather", "really", "somewhat",
    "fairly", "pretty", "incredibly", "absolutely", "totally",
    "completely", "utterly", "highly",
}

ARTICLE_LEMMAS = {"a", "an", "the"}

# Smart jargon: each candidate is verified at module-load time against the
# actual o200k_base tokenizer, and kept ONLY if the abbreviation produces
# strictly fewer tokens than the original. Naive "shorter is better" thinking
# fails because BPE rewards corpus-frequent strings, not short ones — e.g.
# "database" is already 1 token, so "db" gives no token benefit.
_JARGON_CANDIDATES = {
    "synchronization": "sync",
    "synchronizations": "syncs",
    "synchronize": "sync",
    "synchronizes": "syncs",
    "synchronized": "synced",
    "synchronizing": "syncing",
    "infrastructure": "infra",
    "infrastructures": "infras",
    "implementation": "impl",
    "implementations": "impls",
    "configurations": "configs",
    "configuration": "config",
    "specifications": "specs",
    "specification": "spec",
    "repositories": "repos",
    "repository": "repo",
    "documentations": "docs",
    "applications": "apps",
    "application": "app",
    "environments": "envs",
    "environment": "env",
    "databases": "dbs",
    "database": "db",
    "authentications": "auths",
    "authentication": "auth",
    "authorizations": "authzs",
    "authorization": "authz",
    "documentation": "docs",
    "performance": "perf",
}


def _build_verified_jargon() -> dict[str, str]:
    try:
        import tiktoken
    except ImportError:
        return {}
    enc = tiktoken.get_encoding("o200k_base")
    return {
        orig: abbr
        for orig, abbr in _JARGON_CANDIDATES.items()
        if len(enc.encode(orig)) > len(enc.encode(abbr))
    }


JARGON_MAP = _build_verified_jargon()
_JARGON_RE = (
    re.compile(
        r"\b(" + "|".join(re.escape(k) for k in sorted(JARGON_MAP, key=len, reverse=True)) + r")\b",
        re.IGNORECASE,
    )
    if JARGON_MAP
    else None
)


def apply_jargon(text: str) -> str:
    """Abbreviate multi-token jargon to fewer-token forms. Case-preserving."""
    if _JARGON_RE is None:
        return text

    def _sub(m: re.Match) -> str:
        word = m.group(1)
        repl = JARGON_MAP[word.lower()]
        if word.isupper():
            return repl.upper()
        if word[0].isupper():
            return repl.capitalize()
        return repl

    return _JARGON_RE.sub(_sub, text)

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

FILLER_CLAUSES = re.compile(
    r"\b(?:as an AI(?: assistant)?|as a language model|I'd be happy to"
    r"|I can help (?:you )?with that|let's (?:dive into|explore|go through))\b[^.]*\.?\s*",
    re.IGNORECASE,
)


@lru_cache(maxsize=1)
def _nlp():
    import spacy
    return spacy.load("en_core_web_sm")


def _drop_token(tok) -> bool:
    if tok.pos_ == "DET" and tok.lemma_.lower() in ARTICLE_LEMMAS:
        return True
    if tok.dep_ in ("aux", "auxpass"):
        return True
    if tok.pos_ == "ADV" and tok.lemma_.lower() in INTENSIFIER_LEMMAS:
        return True
    return False


def cavemanize_nlp(text: str, *, abbreviate: bool = True) -> str:
    text = FILLER_CLAUSES.sub("", text)
    text = HEDGES.sub("", text)
    text = PLEASANTRIES.sub("", text)
    text = CONNECTIVES.sub("", text)
    if abbreviate:
        text = apply_jargon(text)

    doc = _nlp()(text)
    parts: list[str] = []
    for tok in doc:
        if _drop_token(tok):
            # If dropping the token would merge the previous kept token with
            # the next one (e.g. "you" + "'re" + "creating" → "youcreating"),
            # insert a single space.
            if parts and tok.whitespace_ and not parts[-1].endswith((" ", "\n", "\t")):
                parts.append(" ")
            continue
        parts.append(tok.text_with_ws)
    text = "".join(parts)

    text = re.sub(
        r"(^|[.!?]\s+)([a-z])",
        lambda m: m.group(1) + m.group(2).upper(),
        text,
    )
    text = re.sub(r"\s*,\s*,", ",", text)
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n[ \t]+", "\n", text)
    text = re.sub(r"[ \t]+\n", "\n", text)
    text = re.sub(r"\n{3,}", "\n\n", text)

    return text.strip()


if __name__ == "__main__":
    import sys
    src = sys.stdin.read()
    sys.stdout.write(cavemanize_nlp(src))
