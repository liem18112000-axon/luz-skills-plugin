---
name: prompt-compress
description: Compress text for LLM token savings. TWO MODES — (1) input mode rewrites an English prompt or instruction file as Wenyan/文言文 (~70% reduction) using two local HuggingFace models; (2) output mode takes a saved AI response (English, modern Chinese, or Wenyan), reverse-translates to English if needed, then applies rule-based caveman simplification (~25-40% reduction). All-local, no API keys after install. Trigger on `/prompt-compress <file>` (input mode) or `/prompt-compress --output <file>` (output mode), or natural-language equivalents like "compress this prompt", "wenyan-compress", "shrink this AI response", "cavemanize this output". NOT for code files (.py/.js/.json/etc), user-facing prose, or anything where word-for-word audit matters.
---

# prompt-compress

Two modes share the same skill, the same protect/restore safety net, and the same four local HuggingFace models.

## Dispatch

Read the user's invocation:

- `/prompt-compress <file>` (no flags) → **Input mode** (Mode 1).
- `/prompt-compress --output <file>` OR phrasing like "compress this AI response" / "shrink this output" / "cavemanize this" → **Output mode** (Mode 2).

Both modes accept `--dry-run` (don't write, just print the report).

---

# Mode 1 — input compression (English prompt → Wenyan)

Takes an English prompt or instruction file, rewrites it as Wenyan (Classical Chinese) for the LLM to read. Output is opaque to humans.

## Step 1.1 — Validate input

Refuse and exit if any of these hold:

- File extension not in `.md`, `.txt`, `.tex`, `.typ`, or extensionless.
- File < 100 chars of prose.
- > 50 % of lines are inside fenced code blocks.

## Step 1.2 — Caveman-compress in English (you do this)

Read the file. Rewrite the **prose only** using the rules below. **Do not touch**: code blocks (anything between triple-backticks), inline backtick code, URLs, file paths, headings, list bullets, table syntax, or anything inside `<!-- preserve -->...<!-- /preserve -->`.

Write the result to `<file>.tmp.caveman.md`.

### The 9 rules (from wilpel/caveman-compression SPEC v1.0)

1. **Sentence atomicity** — one fact per sentence. Break compound sentences.
2. **2–5 words per sentence** — exceptions allowed for constraints (6–7 ok).
3. **Strip connectives** — drop because/since/however/although/therefore/thus/in order to/so that. Express cause-effect via sentence order instead.
4. **Active voice + present tense** — "function calculates value", not "value is calculated by the function". Past tense only when temporally meaningful.
5. **Preserve specifics** — keep exact numbers, dates, names. "15 engineers" not "a few".
6. **Drop intensifiers only** — strip very/extremely/quite/rather/really/somewhat. Keep meaningful descriptors (quickly, critical, optional, same, never).
7. **Drop articles** — a/an/the gone unless ambiguous.
8. **Keep unambiguous pronouns** — short pronouns (it/we/he/she) ok when antecedent clear; replace if ambiguous.
9. **Logical completeness** — every inference step explicit. Reader must be able to reconstruct the reasoning chain.

### Anti-patterns to refuse

- Telegraphic ambiguity: `Function error return null` (word-order ambiguous).
- Over-compression: `Try fix` (skips intermediate steps).
- Information addition: never inject claims absent from the source.

## Step 1.3 — Translate to Wenyan

Run:

```bash
~/.claude/skills/prompt-compress/scripts/compress.sh \
    --in '<file>.tmp.caveman.md' \
    --out '<file>.tmp.wenyan.md'
```

The script:

1. Protects code/URLs/numbers/paths/`<!-- preserve -->` blocks as `XPHX####XPHX` sentinels.
2. Splits into sentences.
3. EN → modern ZH via `Helsinki-NLP/opus-mt-en-zh`.
4. ZH → Wenyan via `raynardj/wenyanwen-chinese-translate-to-ancient`.
5. Restores sentinels.
6. Verifies every sentinel restored. **Exits 2** if any went missing.
7. Prints a JSON report.

If the script exits non-zero or emits `placeholders_lost > 0`, ABORT — print stderr and stop.

## Step 1.4 — Validate by round-trip

Read `<file>.tmp.wenyan.md`. Mentally decompress the Wenyan back to English. Compare against the original source file (NOT the caveman tmp).

Build two sets:

- **Original facts**: every number, named entity, code identifier, file path, URL, technical term, and explicit constraint in the source.
- **Wenyan facts**: same set extracted from your decompressed-back-to-English read.

If any original fact is **missing** from the Wenyan set, ABORT. If a fact was added (Wenyan implies something the original didn't say), ABORT — that's a hallucination.

## Step 1.5 — Commit (input mode)

If validation passes:

1. If `--dry-run`: print the report + a 10-line preview. Delete tmp files. Exit.
2. Otherwise:
   - `mv <file> <file>.original.md` (backup)
   - `mv <file>.tmp.wenyan.md <file>.wenyan.md`
   - `rm <file>.tmp.caveman.md`
3. Print the report.

---

# Mode 2 — output compression (AI response → caveman English)

Takes a saved AI response (in any of EN / modern ZH / Wenyan) and rewrites it in caveman English. Useful for:

- Compressing a long Claude response before pasting it into another context.
- Normalizing a response that came back in Chinese or Wenyan (because the system prompt was Wenyan-compressed and the model continued the convention).

## Step 2.1 — Validate input

- File extension `.md`, `.txt`, `.log`, or extensionless.
- File at least 50 chars.
- No language-detection refusal — output mode handles all three languages.

## Step 2.2 — Run the output pipeline

Run:

```bash
~/.claude/skills/prompt-compress/scripts/compress_output.sh \
    --in '<file>' \
    --out '<file>.tmp.caveman.md'
```

The script:

1. Detects language (EN / ZH / Wenyan) by Han-character ratio + classical particle markers (之/也/矣/乎/焉/哉/而/者/其/於) vs modern markers (的/了/是/在/我们/什么).
2. If Wenyan: `wenyanwen-ancient-translate-to-modern` → `opus-mt-zh-en` → English.
3. If modern ZH: `opus-mt-zh-en` → English.
4. If EN: skip translation.
5. Protects code/URLs/numbers (same `XPHX####XPHX` sentinel mechanism as input mode).
6. Applies rule-based caveman simplifier (`scripts/cavemanize.py`): strips intensifiers, hedges, pleasantries, AI-filler clauses, sentence-level connectives, and articles. Re-capitalizes sentence starts. Collapses whitespace.
7. Restores sentinels.
8. Prints a JSON report: `{detected_lang, tokens_in, tokens_after_translate, tokens_out, pct_saved_total, pct_saved_caveman_only, placeholders_protected, placeholders_lost}`.

You can override detection with `--force-lang en|zh|wy` if it misclassifies (mixed-language paragraphs sometimes do).

## Step 2.3 — Validate (output mode)

Lighter than input-mode validation — the goal is "cheap reduction with no loss of facts", not "round-trip lossless".

Read `<file>.tmp.caveman.md` and the original. Spot-check:

- Every number in the original appears in the output.
- Every code identifier, file path, and URL in the original appears in the output.
- No new claims appear that weren't in the original.

If a number or path is missing → ABORT. (Caveman simplification doesn't remove these by design; if any are gone it's a placeholder-restore bug.)

If sentence rewording dropped some tone/nuance → that's expected, not a fail.

## Step 2.4 — Commit (output mode)

1. If `--dry-run`: print the report + a 10-line preview. Delete tmp. Exit.
2. Otherwise:
   - If the user passed `--in-place`: `mv <file> <file>.original.md` then `mv <file>.tmp.caveman.md <file>`.
   - Otherwise: `mv <file>.tmp.caveman.md <file>.compressed.md`. Leave the original untouched.
3. Print the report.

Default behavior is **non-destructive** for output mode (writes alongside, doesn't replace) — output text is more often pasted forward than mutated in place.

---

## Hard boundaries (both modes)

- NEVER run on `.py`, `.js`, `.ts`, `.tsx`, `.jsx`, `.json`, `.yaml`, `.yml`, `.go`, `.rs`, `.java`, `.c`, `.cpp`, `.h`, `.sql`.
- NEVER touch lines containing: `WARNING`, `DANGER`, `IRREVERSIBLE`, `rm -rf`, `DROP TABLE`, `force-push`, `--no-verify`. Leave them in English verbatim.
- NEVER overwrite the source without first writing `<file>.original.md`.
- Anything between `<!-- preserve --> ... <!-- /preserve -->` stays English verbatim in both modes.

## First-run

If `compress.sh` or `compress_output.sh` errors with "Model(s) missing", tell the user:

> Models not installed. Run: `bash ~/.claude/skills/prompt-compress/install.sh`
> Downloads ~3 GB to `~/.claude/skills/prompt-compress/models/` (4 models total: 2 forward + 2 reverse).

Do not run `install.sh` automatically — it's a network-heavy one-time operation, ask the user first.
