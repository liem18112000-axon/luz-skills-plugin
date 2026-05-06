# Design — `prompt-compress`

A Claude Code skill that compresses English text for LLM token savings using:

- **Input mode**: Claude itself, applying the wilpel/caveman-compression 9-rule SPEC at a chosen intensity, post-validated by a Python script that checks every protected span (code, URLs, paths, numbers) survived the rewrite.
- **Output mode**: Default is spaCy POS-aware token drops + a verified-jargon dict (only entries that strictly save tokens under o200k_base) + the same regex phrasal stripping. Fallback `--engine regex` for the pure-regex path (1ms vs 2-3s startup, ~half the savings).

No MT models. No torch/transformers. Deps: `tiktoken` + `spacy` + `en_core_web_sm` (~30 MB total).

## Why no Chinese, no MT

Earlier versions tried EN→ZH translation (input) and ZH→EN reverse-translation (output) via `Helsinki-NLP/opus-mt-en-zh` + `opus-mt-zh-en`. Both broke:

- **Input EN→ZH**: chars −58 % but tokens **+63 %** under `o200k_base`. opus-mt-en-zh emits verbose Chinese with redundant connectives — Han density advantage was wiped out.
- **Output ZH→EN**: hallucinated proper nouns (`Slack` → `Shrek`), mangled URLs (`https://wiki.example.com/runbooks/hotfix` split into `https://wiki.com/` + `example.` + `https://staging.com/runbooks/hotfix`), emitted filler like `"I'm sorry, py."` and `"I'm not what I'm talking about."`. Placeholders technically survived but surrounding prose was destroyed.

Both paths were removed. The skill is now pure English, pure Python regex + Claude.

## Two modes

### Input mode — Claude-driven 9-rule rewrite + script validation

For compressing prompt files, system instructions, RAG chunks, or any English instructional text *before* it reaches the model.

```
Original English file
    │
    ▼
[1] Claude rewrites prose per the 9-rule SPEC at chosen intensity.
    Code blocks, inline `code`, URLs, paths, numbers, <!-- preserve --> blocks
    are copied verbatim — Claude is instructed to leave them alone.
    Output: <file>.tmp.caveman.md
    │
    ▼
[2] Script validates: scripts/compress.py
    - Extract protected spans from original via scripts/protect.py:split_segments.
    - Extract protected spans from rewrite (same function).
    - For each span in original, check it appears (verbatim, same count) in rewrite.
    - If any span is missing → exit 2 and dump which spans were dropped.
    - Compute tokens_in / tokens_out via o200k_base.
    │
    ▼
[3] Claude reads the validated rewrite, spot-checks prose facts
    (named entities, dates expressed as words, technical terms not caught
    by the regex protection in step 2).
    │
    ▼
[4] Backup → <file>.original.md
    Write   <file>.compressed.md
```

The fact-preservation guarantee comes from two layers:

- **Structural** (step 2): code, URLs, paths, numbers are extracted by regex from BOTH files and compared. Anything regex-protectable is verified by the script.
- **Semantic** (step 3): Claude reads the rewrite and confirms named entities, technical terms, and word-form dates appear correctly.

This is stronger than the wilpel reference implementation, which only diffs *facts* (numbers + named entities) without checking code/URL byte-equivalence. We diff both.

### Output mode — three paths

1. **Fast (default, `--engine spacy`)**: spaCy POS pass + verified-jargon dict + regex phrasal stripping. ~7-23% saved on real text. No Claude rewrite cost.
2. **Fast regex (`--engine regex`)**: pure regex. ~4-18% saved. ~1ms vs spaCy's 2-3s startup. Use when you have lots of small files or want zero spaCy cost.
3. **Deep (`--deep`)**: Claude rewrites the response per the 9-rule SPEC, then `compress.sh` validates protected spans. ~46-60% saved on AI-style output (filler-heavy), ~17% on documentation-style tech prose (already terse). Same machinery as input mode — just pointed at AI output instead of prompts. Costs Claude tokens for the rewrite step but produces wilpel-LLM-tier compression.

#### Fast path — POS-aware caveman simplification (spaCy default)

For compressing a saved AI response *after* the fact, before pasting it forward.

```
AI response (English)
    │
    ▼
[1] protect.py:protect() replaces code/URLs/paths/numbers with XPHX{LABEL}XPHX sentinels.
    │
    ▼
[2] Engine pass — default: cavemanize_nlp.py (spaCy)
    a. Phrasal regex strips hedges, pleasantries, connectives, AI-filler.
    b. Verified-jargon dict (synchronization → sync, infrastructure → infra, …).
       Each entry checked at module-load against o200k_base, kept only if it
       strictly saves tokens. 18 of 29 candidates rejected at verification.
    c. spaCy POS pass:
       - DET tokens with article lemmas (a/an/the) → drop
       - dep_ in {aux, auxpass} → drop ("is running", "was created")
       - ADV with intensifier lemmas (very, extremely, …) → drop
       - Whitespace heal so contractions don't merge with neighbors
    d. Whitespace cleanup, sentence-start re-capitalization.

    Fallback (--engine regex): cavemanize.py
    Same phrasal regex + blunt token-level regex (drops every "the", every
    intensifier). ~1ms vs spaCy's 2-3s startup, ~half the savings on tech prose.
    │
    ▼
[3] protect.py:restore() puts the protected spans back.
    │
    ▼
Write <file>.compressed.md (or <file> if --in-place)
```

spaCy first-call: ~2-3s (model load, then cached for the process). Subsequent calls: ~30ms.

#### Deep path — Claude-driven rewrite (`--deep`)

Identical to input mode's pipeline (Step 1.2 → 1.3 → 1.4 in SKILL.md), with output-mode commit semantics (default non-destructive write to `<file>.compressed.md`). Validator (`compress.sh`) is shared between both flows.

Fact preservation comes from the same two layers as input mode:
- **Structural**: protected spans (code, URLs, paths, numbers) extracted by regex from BOTH original and rewrite, verbatim+multiplicity diff.
- **Semantic**: Claude reads the rewrite, spot-checks named entities, technical terms, dates expressed as words.

Output-mode validation tolerance is *lighter* than input mode — losing tone or rephrasing fluff is fine, losing facts is not. Anti-pattern: a rewrite that changes a name, a number, or implies something the original didn't.

## Intensity ladder (input mode only)

Borrowed from JuliusBrussee/caveman, applied to the 9-rule SPEC.

| Level | Behaviour | Tech prose | Chat-style |
|---|---|---|---|
| `lite` | Drop intensifiers, hedges, pleasantries, AI-filler. Keep articles + full sentences. | ~5-10% | ~15-25% |
| `full` (default) | Drop articles too. Allow fragments. Apply all 9 rules. | ~15-25% | ~30-50% |
| `ultra` | Drop conjunctions. Abbreviate jargon. Aggressive sentence merging. | ~25-40% | ~50-70% |

`ultra` brushes against wilpel's "telegraphic ambiguity" anti-pattern — use it only when you trust the consumer model to disambiguate from context.

## Where the skill fails

- **Output is denser to read.** Caveman EN is still English but reads telegraphically. For files only an LLM ever reads — never for user-facing prose, code files, or anything where word-for-word audit matters.
- **Output mode on technical prose**: only ~3-8 % saved. Cavemanize removes filler, technical prose has little filler. Use input mode for higher compression on technical content.
- **Output mode on chat-style AI text**: ~15-25 %. Filler-heavy.

## Sentinels (output mode only)

Output mode uses `protect()` / `restore()` with ` XPHX{LABEL}XPHX ` markers (LABEL = 4 distinct uppercase letters, base 26·25·24·23 = 358,800 indices). Sentinels only need to survive a single Python regex pass — no MT model — so they are completely robust here.

Input mode does NOT use sentinels — the validator in step 2 compares protected-span sets directly, no marker round-trip needed.

## File layout (as built)

```
~/.claude/skills/prompt-compress/
├── SKILL.md                # Claude-facing skill spec
├── requirements.txt        # tiktoken (only)
├── install.sh              # venv + pip install (no model download)
├── docs/
│   └── design.md           # this file
└── scripts/
    ├── compress.sh         # input-mode launcher (Claude calls after rewrite step)
    ├── compress.py         # input-mode validator (protected-span diff + token report)
    ├── compress_output.sh  # output-mode launcher
    ├── compress_output.py  # output-mode pipeline (protect → cavemanize → restore)
    ├── cavemanize.py       # rule-based EN simplifier
    └── protect.py          # placeholder extract/restore + split_segments helper
```

No `models/` directory. No `translate.py`. The skill is ~12 KB of Python total.

## Boundaries

Hard rules baked into SKILL.md:

- Never run on `.py`, `.js`, `.ts`, `.tsx`, `.jsx`, `.json`, `.yaml`, `.yml`, `.go`, `.rs`, `.java`, `.c`, `.cpp`, `.h`, `.sql`.
- Never touch lines containing `WARNING`, `DANGER`, `IRREVERSIBLE`, `rm -rf`, `DROP TABLE`, `force-push`, `--no-verify` — leave English verbatim.
- Never overwrite the source without first writing `<file>.original.md`.
- Anything between `<!-- preserve --> ... <!-- /preserve -->` stays English verbatim in both modes.

## Smoke-test results (2026-05)

| Test | Engine | tokens_in → out | % saved |
|---|---|---|---|
| Tech prose (JWT migration doc) | output / regex | 652 → 625 | 4.1% |
| Tech prose (JWT migration doc) | output / **spacy** (default) | 652 → 604 | **7.4%** |
| Jargon-heavy (synthetic, lots of `synchronization`/`infrastructure`) | output / regex | 191 → 181 | 5.2% |
| Jargon-heavy | output / **spacy** + jargon | 191 → 169 | **11.5%** |
| Chat-style AI text | output / regex | 252 → 207 | 17.9% |
| Chat-style AI text | output / **spacy** + jargon | 252 → 195 | **22.6%** |
| Chat-style AI text | output / **deep** (Claude `full`) | 252 → 102 | **59.5%** |
| Tech-AI Q&A (Postgres) | output / **deep** (Claude `full`) | 496 → 267 | **46.2%** |
| Tech doc (JWT migration) | output / **deep** = input / `full` | 652 → 538 | **17.5%** |

**Deep-mode savings track filler density, not topic.** Documentation-style tech writing is already terse (~15-20% saved). AI-output tech writing carries pleasantries (`Great question!`, `I'd be happy to`, `Hope this helps!`) and saves much more (~45-60%). Decide per-source, not per-genre.

**Failed approaches (kept here as warnings):**
- Output ZH reverse-translation (`opus-mt-zh-en`): hallucinated proper nouns ("Slack" → "Shrek"), mangled URLs. Removed.
- Input EN → modern ZH (`opus-mt-en-zh`): chars −58%, tokens **+63%** under o200k_base. Verbose Chinese MT output defeats the Han-density advantage. Removed.
- Vowel stripping / consonant compression: chars −25%, tokens **+54%**. BPE punishes deviations from corpus distribution. Never built into the skill.
- Naive jargon dict (`database` → `db`, etc.): chars down, tokens flat or up — `database` and `db` are both 1 token under o200k_base. Replaced with a verifier-filtered dict.

## Smart jargon dict — discipline

The jargon abbreviation pass is gated by an **empirical verifier**: at module-load time, each candidate is run through `tiktoken.get_encoding("o200k_base")` and kept only if `len(encode(orig)) > len(encode(abbr))`. As of writing, 11 of 29 hand-picked candidates survive verification. Notable rejections:

- `database` → `db`: both 1 token, no gain
- `repository` → `repo`: both 1 token, no gain
- `authorization` → `authz`: 1 token → **2 tokens**, would COST tokens
- `application`, `environment`, `documentation`: all already 1 token

The 11 entries that pass tend to be longer/less common: `synchronization` (3t → 1t, biggest win), `infrastructure`, `specification`, `documentations` (plural — singular is 1t but plural is 2t), `authentications`, `configurations`. The dict can grow but every entry must pass the verifier.

## Open design questions

1. **Should `--intensity ultra` ship?** Wilpel's SPEC explicitly calls out telegraphic ambiguity as an anti-pattern, which is what `ultra` produces. Default `full` is the safer ceiling. Ship `ultra` as opt-in only.
2. **Statusline savings badge** (à la JuliusBrussee/caveman) — not built. Would need a hook to tally cumulative savings across sessions.
3. **MCP middleware that compresses tool descriptions before they hit the model context** (à la `caveman-shrink`) — out of scope for this skill, separate concern.
