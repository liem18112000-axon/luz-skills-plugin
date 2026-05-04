# Design — output compression extension

A second mode for `prompt-compress` that compresses **AI output** instead of input files. Combines the two reference projects:

- `wilpel/caveman-compression` — algorithmic caveman rule set (the SPEC) applied to text.
- `JuliusBrussee/caveman` — Claude Code skill that constrains the model's response style by prompt injection, with intensity ladder (lite / full / ultra).

This sketch covers both the **post-hoc rewrite** path (analogous to wilpel's tool, applied to a saved response) and the **live style constraint** path (analogous to JuliusBrussee's skill).

## Why this is harder than input compression

Input compression has a clean entry point: the user names a file and we transform it. Output compression has three different entry points, and the choice of entry point determines almost everything else:

1. **Live style constraint** — the model is *asked* to reply in caveman style. Cheapest, no extra round-trips, but only works for *future* responses, and the model must obey the constraint. This is the JuliusBrussee approach.
2. **Post-hoc rewrite** — a saved response is rewritten in caveman style after the fact. Works on any past output, but needs a second model pass (either us, or a sub-LLM call). This is the wilpel approach applied to output text.
3. **Stop-hook interception** — a Claude Code `Stop` hook grabs the last assistant message and either stores a compressed copy or warns. Cannot retroactively *replace* what the user already saw, so it's mostly useful for cost telemetry, not real compression.

We'll implement (1) and (2). Skip (3) for now.

## Special twist — reverse-translation when output is non-English

When `prompt-compress` is used aggressively, the system prompt may end up in Wenyan. The model, taking its cue from surrounding context, sometimes replies in Chinese or Wenyan rather than English. Before applying the caveman *style* rules — which are English-grammar-aware — we have to translate the response back to English first.

So the pipeline is:

```
AI response (string)
    │
    ▼
[a] Detect script: EN / ZH-modern / Wenyan
    │
    ├── EN  → skip translation
    │
    ├── ZH-modern (Han chars, modern grammar) → opus-mt-zh-en → EN
    │
    └── Wenyan (Han chars, classical grammar) → wenyanwen-ancient-to-modern → opus-mt-zh-en → EN
    │
    ▼
[b] Apply caveman SPEC rules (the 9 from input compression, applied to EN)
    │
    ▼
EN caveman output (the user-visible result)
```

Note: this is the **reverse** of the input pipeline. Input goes EN→ZH→Wenyan; output goes Wenyan→ZH→EN.

## Models needed

In addition to the two already installed:

| Model | Direction | Size | Purpose |
|-------|-----------|------|---------|
| `Helsinki-NLP/opus-mt-en-zh` | EN → ZH | ~300 MB | (already installed) input pipeline |
| `raynardj/wenyanwen-chinese-translate-to-ancient` | ZH → Wenyan | ~500 MB | (already installed) input pipeline |
| **`Helsinki-NLP/opus-mt-zh-en`** | **ZH → EN** | **~300 MB** | **NEW** for output reverse |
| **`raynardj/wenyanwen-ancient-translate-to-modern`** | **Wenyan → ZH** | **~500 MB** | **NEW** for output reverse |

Total install footprint roughly doubles to ~3 GB. Cold start for a Wenyan-input round-trip jumps to ~30 s on CPU (4 model loads).

## Language detection

Heuristic — count Han characters, classify by ratio and grammar markers:

```python
def detect(text: str) -> str:
    n = len(text)
    han = sum(1 for c in text if "一" <= c <= "鿿")
    if n == 0 or han / n < 0.10:
        return "en"
    # Modern-Chinese markers: 的, 了, 是, 在, 我们, 你们 — frequent function words.
    # Wenyan markers: 之, 也, 矣, 乎, 焉, 哉, 而 — frequent classical particles.
    modern = sum(text.count(w) for w in ("的", "了", "是", "在", "我们", "你们"))
    classical = sum(text.count(w) for w in ("之", "也", "矣", "乎", "焉", "哉", "而"))
    return "wy" if classical > modern else "zh"
```

Imperfect — bilingual or mixed text falls into whichever camp wins. Acceptable for v1; if it misclassifies, the next pipeline stage will simply produce slightly worse output (still readable, since both reverse paths terminate in English).

## Mode 1 — post-hoc rewrite (`/prompt-compress --output <file>`)

Adds a flag to the existing skill. The argument is a text file containing a saved AI response (any language).

### Pipeline

1. Read `<file>`.
2. Run language detection → `en` / `zh` / `wy`.
3. If `wy`: translate Wenyan → modern ZH (new HF model). Result becomes ZH path.
4. If `zh` (or after step 3): translate ZH → EN (new HF model). Result is English.
5. Apply the 9-rule caveman SPEC to the English text. Two implementation choices for step 5:
   - **(a) Rule-based, offline**: spaCy + a small rewriter that drops articles, intensifiers, connectives, and splits long sentences. Same approach as `wilpel/caveman_compress_nlp.py`. ~15-30% reduction. No model needed.
   - **(b) LLM-based**: ask Claude itself (the host model) to rewrite in caveman style following the 9 rules, exactly as the input pipeline does step 1. Higher quality (~40-58%) but needs an extra Claude turn.

   Recommend (a) for v1 — keeps the skill standalone and avoids burning Claude tokens on its own output.
6. Print the result. If `--write <out>` is passed, save to `<out>`; otherwise stream to stdout.

### Script extension

Add `scripts/decompress.py` (Wenyan→ZH→EN) symmetric to `scripts/compress.py` and a small `scripts/cavemanize.py` that applies the rule-based EN simplifier:

```
scripts/
├── compress.sh           # existing — input pipeline launcher
├── compress.py           # existing — EN → ZH → Wenyan
├── decompress.py         # NEW — Wenyan/ZH → EN
├── cavemanize.py         # NEW — EN → caveman EN (rule-based)
├── translate.py          # extend with zh_to_en + wenyan_to_zh
├── protect.py            # unchanged
└── output.sh             # NEW — entry point: detect + decompress + cavemanize
```

`scripts/output.sh` invocation:

```bash
~/.claude/skills/prompt-compress/scripts/output.sh \
    --in <response.txt> --out <compressed.txt>
```

### `cavemanize.py` outline

A pure-Python implementation of the rules wilpel ships in `caveman_compress_nlp.py`, simplified — no spaCy dependency to keep install size down:

```python
import re

INTENSIFIERS = r"\b(very|extremely|quite|rather|really|somewhat)\s+"
ARTICLES     = r"\b(a|an|the)\s+"
AUX_VERBS    = r"\b(is|are|was|were|am|be|been|being|have|has|had|do|does|did)\b\s*"
HEDGES       = r"\b(I think|I believe|it seems|perhaps|maybe|kind of|sort of)\b\s*,?\s*"
PLEASANTRIES = r"\b(please|thanks|thank you|sure|of course|certainly|absolutely)\b\s*,?\s*"
CONNECTIVES  = r"\b(however|therefore|moreover|furthermore|consequently|nevertheless|in order to|as a result)\b\s*,?\s*"

def cavemanize(text: str) -> str:
    for pat in (INTENSIFIERS, HEDGES, PLEASANTRIES, CONNECTIVES):
        text = re.sub(pat, "", text, flags=re.IGNORECASE)
    # Drop articles only outside of code blocks / inline code (use protect.py first)
    text = re.sub(ARTICLES, "", text, flags=re.IGNORECASE)
    # Compact whitespace
    text = re.sub(r"\s+", " ", text).strip()
    return text
```

Pre-process with `protect.py` so code, URLs, and numbers survive untouched. Same sentinel mechanism as input compression.

## Mode 2 — live style constraint (`/prompt-compress --style [lite|full|ultra]`)

This is the JuliusBrussee approach: instead of rewriting after the fact, push a constraint into the conversation so future replies are already in caveman style.

### Mechanism

Toggle a session-scoped instruction by writing to user memory or appending a CLAUDE.md directive. The skill provides three preset directives matching JuliusBrussee's intensity ladder:

```
lite  : "Reply briefly. Drop filler and pleasantries. Keep grammar and articles intact."
full  : "Reply terse like smart caveman. Drop articles, hedging, filler. Fragments OK.
         Keep technical terms exact. Code blocks unchanged."
ultra : "Telegraphic. Abbreviate jargon (DB, auth, cfg). Strip conjunctions. Keep code/URLs/numbers exact.
         Pattern: '[thing] [action] [reason]. [next step].'"
```

### Boundaries (copied from JuliusBrussee — non-negotiable)

The constraint must include explicit auto-clarity exceptions:

- Drop caveman style for security warnings, irreversible confirmations, multi-step sequences with order-dependent steps.
- Code blocks always written normally.
- `stop caveman` / `normal mode` reverts.

### Why live constraint and post-hoc rewrite are both needed

- **Live** is cheaper (no extra Claude or HF round-trip) but only affects future responses and depends on the model honoring the constraint.
- **Post-hoc** works on any text including pasted responses from other models, and is deterministic (rule-based), but adds latency.

The two complement each other: live for normal day-to-day savings, post-hoc for batch-compressing a transcript or normalizing a non-English response that snuck through.

## SKILL.md — proposed updates

Extend the existing skill rather than create a new one. Add a third section after the input pipeline:

```
## Mode: input compression  (existing — /prompt-compress <file>)
   ...

## Mode: output rewrite     (new — /prompt-compress --output <file>)
   1. Read <file>. Detect language.
   2. If non-English: run scripts/decompress.py to reverse-translate to English.
   3. Apply scripts/cavemanize.py.
   4. Write to <out> or stdout.

## Mode: live style         (new — /prompt-compress --style [lite|full|ultra|off])
   1. Append the chosen directive to CLAUDE.md (or remove on `off`).
   2. Confirm to user that the directive is active for the rest of the session.
```

## Open questions

1. **Where does the live-style directive live?** Three options: project `CLAUDE.md`, user memory file, or a `SessionStart` hook injecting a system-reminder. The CLAUDE.md route is simplest but mutates a tracked file. The hook route is cleanest but requires a settings.json change. Recommend: project `CLAUDE.md` for v1, hook for v2.
2. **Two-pass post-hoc?** A response that survives the language reverse-translation may still benefit from a second pass through an LLM rewriter for higher compression. Skip in v1; add as `--style llm` flag later.
3. **Wenyan in code blocks.** If the model emits a Wenyan explanation interleaved with English code, language detection must run paragraph-by-paragraph, not on the whole text. Otherwise the script will try to translate code as if it were Chinese.
4. **Round-trip integrity check.** The input pipeline validates by round-trip. The output pipeline could too: after cavemanize, ask Claude to expand back and diff facts against the original response. Worth doing only if the user reports lost meaning in practice.

## Effort estimate

- Two new HF models cached on first install (extends `install.sh` by ~5 lines): trivial.
- `scripts/decompress.py` symmetric to `compress.py`: ~80 LOC.
- `scripts/cavemanize.py` rule-based: ~50 LOC.
- `scripts/output.sh` launcher: ~10 LOC.
- SKILL.md extension with the new mode docs: ~40 LOC.
- Live-style mode (CLAUDE.md edit): ~30 LOC.

Roughly one afternoon. Ship the post-hoc path first, add the live-style toggle once the round-trip is proven to preserve meaning on real responses.
