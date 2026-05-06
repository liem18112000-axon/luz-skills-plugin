---
name: prompt-compress
description: Compress English text for LLM token savings. Pure Python, no MT models. TWO MODES — (1) input mode rewrites an English prompt or instruction file in caveman style following the wilpel/caveman-compression 9-rule SPEC at chosen intensity (lite/full/ultra), code/URLs/numbers preserved by structural validation, ~15-50% token savings depending on intensity and prose density; (2) output mode applies POS-aware caveman simplification (spaCy + verified-jargon dict, regex fallback via --engine regex) to a saved AI response (~7-25% savings depending on prose style). Trigger on `/prompt-compress <file>` (input) or `/prompt-compress --output <file>` (output), or natural-language equivalents like "compress this prompt", "shrink this AI response", "cavemanize this output". NOT for code files (.py/.js/.json/etc), user-facing prose, or anything where word-for-word audit matters.
---

# prompt-compress

Two modes share the same protect/restore safety net. No MT models — only Claude (host model) for the input-mode rewrite, and Python regex for the output-mode pass.

## Dispatch

- `/prompt-compress <file>` (no flags) → **Input mode** (Mode 1). Claude rewrites EN to caveman-EN per the 9-rule SPEC, then a script validates fact preservation.
- `/prompt-compress --output <file>` → **Output mode fast** (Mode 2 default). spaCy/regex simplification of a saved AI response. ~7-23% saved. Cheap, no Claude rewrite.
- `/prompt-compress --output --deep <file>` → **Output mode deep** (Mode 2 deep). Claude rewrites per 9-rule SPEC, validator confirms facts. ~30-50% saved on chat-style text. Same machinery as input mode but with output-mode commit semantics (non-destructive default).

Phrasing like "compress this AI response" / "shrink this output" / "cavemanize this" maps to Mode 2 fast. Phrasing like "deeply compress this output" / "Claude-rewrite this response" maps to Mode 2 deep.

All modes accept:
- `--dry-run` — don't write, just print the report.

Input mode and Output deep mode also accept:
- `--intensity lite|full|ultra` — default `full`.

---

# Mode 1 — input compression (English prompt → caveman English)

Takes an English prompt or instruction file, rewrites it in caveman style for the LLM to read. Output is denser to read but every fact, code block, URL, and number is preserved — code/URLs/paths/numbers are protected structurally by the validator script in Step 1.3.

## Step 1.1 — Validate input

Refuse and exit if any of these hold:

- File extension not in `.md`, `.txt`, `.tex`, `.typ`, or extensionless.
- File < 100 chars of prose.
- > 50 % of lines are inside fenced code blocks.

## Step 1.2 — Caveman-rewrite (you do this)

Read the file. Rewrite the **prose only** following the 9-rule SPEC at the chosen intensity. **Do not touch**: code blocks (anything between triple-backticks), inline backtick code, URLs, file paths, headings, list bullets, table syntax, or anything inside `<!-- preserve -->...<!-- /preserve -->`.

Write the result to `<file>.tmp.caveman.md`.

### Intensity ladder

| Level | Behaviour | Typical savings (tech prose) | Typical savings (chat-style) |
|---|---|---|---|
| `lite` | Drop intensifiers, hedges, pleasantries, AI-filler. Keep articles + full sentences. | ~5-10% | ~15-25% |
| `full` (default) | Drop articles too. Allow fragments. Apply all 9 rules. | ~15-25% | ~30-50% |
| `ultra` | Drop conjunctions. Abbreviate jargon (`DB`, `auth`, `cfg`, `req`, `cmd`). Aggressive sentence merging. | ~25-40% | ~50-70% |

Savings depend heavily on how much filler the source has. Dense technical prose (URLs, code, fact-laden) compresses less. Wilpel's benchmark on an algorithm explainer landed 20%; on a chatty system prompt 58%. Our smoke test on a JWT migration doc at `full` landed 17.5%.

### The 9 rules (from wilpel/caveman-compression SPEC v1.0)

1. **Sentence atomicity** — one fact per sentence. Break compound sentences.
2. **2–5 words per sentence** — exceptions allowed for constraints (6–7 ok). At `lite` keep full sentences.
3. **Strip connectives** — drop because/since/however/although/therefore/thus/in order to/so that. Express cause-effect via sentence order instead.
4. **Active voice + present tense** — "function calculates value", not "value is calculated by the function". Past tense only when temporally meaningful.
5. **Preserve specifics** — keep exact numbers, dates, names. "15 engineers" not "a few".
6. **Drop intensifiers only** — strip very/extremely/quite/rather/really/somewhat. Keep meaningful descriptors (quickly, critical, optional, same, never).
7. **Drop articles** — a/an/the gone unless ambiguous. Skip at `lite`.
8. **Keep unambiguous pronouns** — short pronouns (it/we/he/she) ok when antecedent clear; replace if ambiguous.
9. **Logical completeness** — every inference step explicit. Reader must be able to reconstruct the reasoning chain.

### Anti-patterns to refuse

- Telegraphic ambiguity: `Function error return null` (word-order ambiguous).
- Over-compression: `Try fix` (skips intermediate steps).
- Information addition: never inject claims absent from the source.

## Step 1.3 — Validate (script)

Run:

```bash
~/.claude/skills/prompt-compress/scripts/compress.sh \
    --orig '<file>' \
    --rewritten '<file>.tmp.caveman.md' \
    --out '<file>.tmp.final.md'
```

The script:

1. Extracts protected spans (code blocks, inline code, URLs, paths, numbers, `<!-- preserve -->` blocks) from BOTH the original and the rewrite.
2. For each span in the original, checks it appears (verbatim, with the same multiplicity) in the rewrite.
3. If any span is missing → exits 2 (FAIL) and prints which spans were dropped.
4. Otherwise → writes `<file>.tmp.final.md` (a copy of the rewrite) and prints `{tokens_in, tokens_out, chars_in, chars_out, protected_in_orig, protected_in_rewritten, protected_missing, pct_saved}` (token counting via `o200k_base`).

If validation fails: read the FAIL output, identify which span got dropped/altered, fix `<file>.tmp.caveman.md`, and re-run Step 1.3. Do NOT skip this — a missing URL or path means downstream consumers will break silently.

## Step 1.4 — Validate by reading (you do this)

Read `<file>.tmp.final.md`. Compare against the original source.

Build two sets:
- **Original facts**: every number, named entity, code identifier, file path, URL, technical term, and explicit constraint in the source.
- **Rewritten facts**: same set extracted from the rewrite.

If any original fact is **missing** from the rewritten set, ABORT. If a fact was added (rewrite implies something the original didn't say), ABORT — that's a hallucination.

(Step 1.3 already verified code-blocks/URLs/paths/numbers structurally. This step catches prose facts the regex doesn't protect — names, technical terms, dates expressed as words like "next Tuesday".)

## Step 1.5 — Commit (input mode)

If validation passes:

1. If `--dry-run`: print the report + a 10-line preview. Delete tmp files. Exit.
2. Otherwise:
   - `mv <file> <file>.original.md` (backup)
   - `mv <file>.tmp.final.md <file>.compressed.md`
   - `rm <file>.tmp.caveman.md`
3. Print the report.

---

# Mode 2 — output compression (AI response → caveman English)

Takes a saved AI response (English) and rewrites it in caveman English using regex rules — no Claude rewrite step, faster but lower quality than input mode. Useful for compressing a long response before pasting it into another context.

## Step 2.1 — Validate input

- File extension `.md`, `.txt`, `.log`, or extensionless.
- File at least 50 chars.
- Source must be English. (Earlier versions detected ZH and reverse-translated via opus-mt-zh-en; the MT hallucinated proper nouns and mangled URLs so that path was removed.)

## Step 2.2 — Run the output pipeline

Run:

```bash
~/.claude/skills/prompt-compress/scripts/compress_output.sh \
    --in '<file>' \
    --out '<file>.tmp.caveman.md'
```

The script:

1. Protects code/URLs/paths/numbers via `XPHX{LABEL}XPHX` sentinels.
2. Applies the chosen engine:
   - `spacy` (default): POS-aware token drops via `scripts/cavemanize_nlp.py`. Strips auxiliary verbs (`is running`, `was created`) via dependency parse, articles via DET POS, intensifiers via lemma+POS. Plus a verified-jargon dict (~11 entries like `synchronization` → `sync`, all empirically token-positive under o200k_base). Plus the same regex phrasal stripping. ~2-3s first-call startup (spaCy model load), ~30ms thereafter.
   - `regex`: pure-regex via `scripts/cavemanize.py`. ~1ms but ~half the savings on tech prose. Fallback for `--engine regex`.
3. Restores sentinels.
4. Prints `{engine, tokens_in, tokens_out, chars_in, chars_out, placeholders_protected, placeholders_lost, pct_saved}`.

Aborts with exit 2 if any placeholder is lost (means a sentinel got mangled — should not happen with current letter-encoding).

Pass `--engine regex` to force the fast path. Default is `spacy`.

## Step 2.3 — Validate (output mode)

Lighter than input mode. Read `<file>.tmp.caveman.md` and the original. Spot-check:

- Every number in the original appears in the output.
- Every code identifier, file path, and URL in the original appears in the output.
- No new claims appear that weren't in the original.

If a number or path is missing → ABORT (placeholder-restore bug; should not happen).

If sentence rewording dropped some tone/nuance → that's expected, not a fail.

## Step 2.4 — Commit (output mode)

1. If `--dry-run`: print the report + a 10-line preview. Delete tmp. Exit.
2. Otherwise:
   - If the user passed `--in-place`: `mv <file> <file>.original.md` then `mv <file>.tmp.caveman.md <file>`.
   - Otherwise: `mv <file>.tmp.caveman.md <file>.compressed.md`. Leave the original untouched.
3. Print the report.

Default behaviour is **non-destructive** for output mode (writes alongside, doesn't replace) — output text is more often pasted forward than mutated in place.

---

# Mode 2 deep — Claude-driven rewrite of AI output (`--deep`)

Same Claude-rewrite-and-validate machinery as Mode 1 (input mode), but applied to a saved AI response with output-mode commit semantics. Use when the fast path's 7-23% isn't enough and you'd rather burn Claude tokens rewriting than paste a longer response forward.

## Step 2.D.1 — Validate input

Same as Step 2.1. File extension `.md`/`.txt`/`.log`/extensionless, ≥50 chars, English.

## Step 2.D.2 — Caveman-rewrite (you do this)

Same as Step 1.2 (input mode). Apply the 9-rule SPEC at the chosen intensity (default `full`). Do not touch code blocks, inline backticks, URLs, file paths, headings, list bullets, table syntax, or anything inside `<!-- preserve -->...<!-- /preserve -->`.

Write the result to `<file>.tmp.caveman.md`.

## Step 2.D.3 — Validate (script)

Run:

```bash
~/.claude/skills/prompt-compress/scripts/compress.sh \
    --orig '<file>' \
    --rewritten '<file>.tmp.caveman.md' \
    --out '<file>.tmp.final.md'
```

Same validator as Mode 1 Step 1.3. Diffs protected spans (code, URLs, paths, numbers) between original and rewrite, exits 2 if any span is missing, otherwise emits `<file>.tmp.final.md` and prints the JSON report.

## Step 2.D.4 — Validate by reading (you do this)

Lighter than Mode 1 Step 1.4. Read `<file>.tmp.final.md`. Spot-check:

- Numbers, named entities, technical terms appear in the rewrite.
- No new claims that weren't in the original.
- Tone/nuance loss is OK (output mode philosophy — pasting forward, not preserving voice).

If a fact (number, name, term) is missing → ABORT.

## Step 2.D.5 — Commit (deep mode)

Same as Step 2.4 (output fast):

1. If `--dry-run`: print the report + a 10-line preview. Delete tmp. Exit.
2. Otherwise:
   - If `--in-place`: `mv <file> <file>.original.md` then `mv <file>.tmp.final.md <file>`.
   - Otherwise: `mv <file>.tmp.final.md <file>.compressed.md`. Original untouched.
   - Delete `<file>.tmp.caveman.md`.
3. Print the report.

Non-destructive by default — same as Mode 2 fast.

---

## Hard boundaries (both modes)

- NEVER run on `.py`, `.js`, `.ts`, `.tsx`, `.jsx`, `.json`, `.yaml`, `.yml`, `.go`, `.rs`, `.java`, `.c`, `.cpp`, `.h`, `.sql`.
- NEVER touch lines containing: `WARNING`, `DANGER`, `IRREVERSIBLE`, `rm -rf`, `DROP TABLE`, `force-push`, `--no-verify`. Leave them in English verbatim.
- NEVER overwrite the source without first writing `<file>.original.md`.
- Anything between `<!-- preserve --> ... <!-- /preserve -->` stays English verbatim in both modes.

## First-run

If `compress.sh` or `compress_output.sh` errors with `ModuleNotFoundError`, tell the user:

> Dependencies not installed. Run: `bash ~/.claude/skills/prompt-compress/install.sh`
> Installs `tiktoken` + `spacy` + `en_core_web_sm` into a local venv (~30 MB total). No MT models, no GPU, no network after first install. If you want the regex-only path with no spaCy, pass `--engine regex` and ignore the missing-spaCy error.

Do not run `install.sh` automatically — ask first.
