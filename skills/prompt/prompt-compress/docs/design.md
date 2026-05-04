# Design — `prompt-compress`

A Claude Code skill that compresses English prompts and instruction files into Wenyan (文言文, Classical Chinese) using two local HuggingFace translation models. No API keys, no network after first install.

## Why Wenyan

Wenyan is denser per-character than English is per-token. Claude tokenizes CJK characters at roughly 1–2 tokens each; English averages ~1.3 tokens per word. A 300-word English prompt that compresses to ~80 Wenyan characters lands at roughly **70–80 % token reduction** for content the model only needs to *read*.

## Where it fails

- Code, file paths, URLs, and numbers must survive translation untouched. They will not, unless we protect them with sentinels before the MT pipeline runs and restore them after.
- Two-stage MT (EN → modern ZH → Wenyan) is lossy. The skill must validate by round-trip before overwriting the source.
- Wenyan output is opaque to humans. This is for files only an LLM ever reads — never for user-facing prose, code files, or anything where word-for-word audit matters.

## Pipeline

```
English source
    │
    ▼
[1] Caveman-compress in English        ← Claude does this, following the 9-rule
    │                                    SPEC inlined in SKILL.md
    ▼
[2] Protect: extract placeholders      ← Python (scripts/protect.py)
    code blocks, inline `code`, URLs, paths, numbers,
    explicit <!-- preserve --> blocks
    → replace with " XPHX####XPHX " sentinels
    │
    ▼
[3] EN → modern ZH                     ← Helsinki-NLP/opus-mt-en-zh (~300 MB)
    │
    ▼
[4] ZH → Wenyan                        ← raynardj/wenyanwen-chinese-translate-to-ancient
    │                                    (~500 MB)
    ▼
[5] Restore placeholders               ← fail loudly if any sentinel went missing
    │
    ▼
[6] Validate by round-trip             ← Claude reads the Wenyan, decompresses
    │                                    mentally, diffs facts against the original.
    │                                    Abort if any fact lost or hallucinated.
    ▼
Backup source → <file>.original.md
Write          <file>.wenyan.md
```

Steps 1, 6 are done by Claude itself (driven by SKILL.md). Steps 2–5 are the Python script `scripts/compress.py` invoked through a thin bash wrapper that picks the right venv python.

## Sentinel design

The protect step replaces every "untouchable" span with a marker of the form `XPHX0000XPHX`, padded with single spaces. Properties chosen for survival through Chinese MT:

- **All-Latin alphanumeric** — Marian and BERT-based Chinese encoders pass these through largely intact (they get tokenized as unknown subwords, but emerge unchanged).
- **Fixed length, fixed prefix/suffix** — easy to grep back out with one regex.
- **Padded with spaces** — prevents the tokenizer from merging the sentinel with a neighboring CJK character. The padding survives restoration but is harmless (an LLM reading the file ignores it).

If any sentinel index goes missing between protect and restore, the script exits **2** rather than silently producing partial output. This is the single most important safety property.

## File layout (as built)

```
~/.claude/skills/prompt-compress/
├── SKILL.md                # Claude-facing skill spec, 9 rules inlined
├── requirements.txt        # transformers, torch, sentencepiece, huggingface_hub, tiktoken
├── install.sh              # bash installer: venv + pip + snapshot_download
├── docs/
│   └── design.md           # this file
├── scripts/
│   ├── compress.sh         # cross-platform venv-python launcher
│   ├── compress.py         # main: protect → en→zh → zh→wenyan → restore → JSON report
│   ├── protect.py          # placeholder extract / restore
│   └── translate.py        # lazy-loaded MarianMT + EncoderDecoder pipelines
└── models/                 # populated on first run by install.sh
    ├── opus-mt-en-zh/
    └── wenyanwen-chinese-translate-to-ancient/
```

Validation (step 6) lives in SKILL.md, not as a separate script — it's driven by the host model, which already has the file contents in context.

## SKILL.md design

```yaml
---
name: prompt-compress
description: Compress an English prompt or instruction file into Wenyan ...
---
```

The body of SKILL.md walks Claude through the six steps above. Three properties of the design matter:

1. **The 9 caveman compression rules are inlined** so Claude does not need to fetch them at runtime. Tokens spent now beat round-trip latency later.
2. **Boundaries listed twice** — once as a refusal list (file extensions, security keywords) and once as escape hatches (`<!-- preserve -->...<!-- /preserve -->`).
3. **First-run guidance** — if the script reports missing models, the skill instructs Claude to tell the user to run `install.sh` rather than running it autonomously, because it's a network-heavy one-time operation.

## Script outlines (design intent)

The actual scripts implement these contracts; the snippets below are the design before the code, kept for reference.

### `scripts/compress.py`

```python
import argparse, json, sys
from protect import protect, restore
from translate import en_to_zh, zh_to_wenyan

def main():
    args = parse_args()                    # --in, --out
    src  = open(args.in_).read()

    protected, placeholders = protect(src)
    zh = "\n".join(en_to_zh(s)     for s in split_sentences(protected))
    wy = "\n".join(zh_to_wenyan(s) for s in split_sentences(zh))
    final, missing = restore(wy, placeholders)

    report = {
        "tokens_in":  count_tokens(src),
        "tokens_out": count_tokens(final),
        "pct_saved":  pct(src, final),
        "placeholders_protected": len(placeholders),
        "placeholders_lost":      len(missing),
    }
    if missing:
        sys.stderr.write(f"FAIL: {len(missing)} placeholders lost: {missing}\n")
        return 2

    open(args.out, "w", encoding="utf-8").write(final)
    print(json.dumps(report))
    return 0
```

### `scripts/protect.py`

```python
import re

PATTERNS = [
    r"<!--\s*preserve\s*-->[\s\S]*?<!--\s*/preserve\s*-->",  # explicit preserves
    r"```[\s\S]*?```",                       # fenced code
    r"`[^`\n]+`",                            # inline code
    r"https?://\S+",                         # URLs
    r"(?:[A-Za-z]:)?[/\\][\w./\\-]+",        # file paths
    r"\b\d+(?:\.\d+)?(?:[a-zA-Z%]+)?\b",     # numbers + units
]
COMBINED = re.compile("|".join(f"(?:{p})" for p in PATTERNS))

def protect(text):
    out = []
    def sub(m):
        out.append(m.group(0))
        return f" XPHX{len(out)-1:04d}XPHX "
    return COMBINED.sub(sub, text), out

def restore(text, placeholders):
    seen = set()
    def unsub(m):
        i = int(m.group(1))
        seen.add(i)
        return placeholders[i] if i < len(placeholders) else m.group(0)
    text = re.sub(r"XPHX(\d{4})XPHX", unsub, text)
    missing = [i for i in range(len(placeholders)) if i not in seen]
    return text, missing
```

### `scripts/translate.py`

```python
from functools import lru_cache
from pathlib import Path
import torch

MODELS_DIR = Path(__file__).resolve().parent.parent / "models"

@lru_cache(maxsize=1)
def _en_zh():
    from transformers import MarianMTModel, MarianTokenizer
    p = MODELS_DIR / "opus-mt-en-zh"
    return MarianTokenizer.from_pretrained(p), MarianMTModel.from_pretrained(p).eval()

@lru_cache(maxsize=1)
def _zh_wy():
    from transformers import AutoTokenizer, EncoderDecoderModel
    p = MODELS_DIR / "wenyanwen-chinese-translate-to-ancient"
    return AutoTokenizer.from_pretrained(p), EncoderDecoderModel.from_pretrained(p).eval()

@torch.no_grad()
def en_to_zh(text):
    tok, model = _en_zh()
    enc = tok(text, return_tensors="pt", truncation=True, max_length=512)
    return tok.batch_decode(model.generate(**enc, max_length=512, num_beams=4),
                             skip_special_tokens=True)[0]

@torch.no_grad()
def zh_to_wenyan(text):
    tok, model = _zh_wy()
    enc = tok(text, return_tensors="pt", truncation=True,
              max_length=128, padding="max_length")
    out = model.generate(enc.input_ids,
                         attention_mask=enc.attention_mask,
                         num_beams=3, max_length=256,
                         bos_token_id=101,
                         eos_token_id=tok.sep_token_id,
                         pad_token_id=tok.pad_token_id)
    return tok.batch_decode(out, skip_special_tokens=True)[0]
```

`lru_cache` keeps both models warm within a single process. Cold start is ~10–20 s on CPU for the pair. Each subsequent translation is ~100–500 ms per sentence. For one-shot file rewrites this is fine; for high-frequency usage promote to a persistent sidecar (FastAPI on `localhost:7891`) and have the wrapper POST to it.

## Boundaries

Hard rules baked into SKILL.md:

- Never run on `.py`, `.js`, `.ts`, `.tsx`, `.jsx`, `.json`, `.yaml`, `.yml`, `.go`, `.rs`, `.java`, `.c`, `.cpp`, `.h`, `.sql`.
- Never touch lines containing `WARNING`, `DANGER`, `IRREVERSIBLE`, `rm -rf`, `DROP TABLE`, `force-push`, `--no-verify` — leave English verbatim.
- Never overwrite the source without first writing `<file>.original.md`.
- Never skip the round-trip validation. The MT pipeline is lossy; validation is what makes the skill safe to use unattended.

## Optional hook variant

If automatic compression on every Write/Edit is wanted (rather than explicit invocation), a `PostToolUse` hook in `settings.json` can detect a `<!-- compress:wenyan -->` marker in the first 200 bytes of the written file and trigger the pipeline:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/skills/prompt-compress/scripts/compress.sh --auto"
          }
        ]
      }
    ]
  }
}
```

The `--auto` flag would tell the script to read `tool_input.file_path` from stdin (Claude Code passes hook event JSON on stdin), check for the marker, and either run the pipeline or exit silently. This is **not** wired by default — the slash-command flow is preferred until the round-trip validation is proven on real content.

## Open design questions

1. **Round-trip preservation rate.** EN → ZH → Wenyan typically loses 15–30 % of facts on first pass; the validation step is what catches losses. Could be improved by training a single EN→Wenyan adapter on top of a larger MT model — out of scope for this skill.
2. **Why two hops, not one?** `raynardj/wenyanwen-chinese-translate-to-ancient` only accepts modern Chinese as input. A direct EN→Wenyan model would be one fewer hop, but the available HuggingFace candidates are noticeably weaker than the two-hop pipeline. Two clean hops beats one bad one.
3. **GPU?** Optional. CPU works for prompts up to a few thousand words. For 50 KB+ docs, GPU cuts wall-clock from ~30 s to ~3 s.
4. **Fallback when validation fails?** The skill currently aborts. An alternative is to fall back to the English caveman compression alone (no Wenyan), with a warning, so the user gets at least *some* token reduction.
