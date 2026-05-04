"""Load and run the four HuggingFace translation models locally.

Forward (input compression): EN → ZH (modern) → Wenyan
Reverse (output decompression): Wenyan → ZH (modern) → EN
"""
from __future__ import annotations

import sys
from functools import lru_cache
from pathlib import Path

import torch

MODELS_DIR = Path(__file__).resolve().parent.parent / "models"
EN_ZH_DIR = MODELS_DIR / "opus-mt-en-zh"
ZH_WY_DIR = MODELS_DIR / "wenyanwen-chinese-translate-to-ancient"
ZH_EN_DIR = MODELS_DIR / "opus-mt-zh-en"
WY_ZH_DIR = MODELS_DIR / "wenyanwen-ancient-translate-to-modern"


def _ensure(dirs: tuple[Path, ...]) -> None:
    missing = [d for d in dirs if not (d / "config.json").exists()]
    if missing:
        names = ", ".join(d.name for d in missing)
        sys.stderr.write(
            f"Model(s) missing under {MODELS_DIR}: {names}\n"
            f"Run: bash {MODELS_DIR.parent}/install.sh\n"
        )
        raise SystemExit(3)


@lru_cache(maxsize=1)
def _en_zh():
    from transformers import MarianMTModel, MarianTokenizer
    _ensure((EN_ZH_DIR,))
    tok = MarianTokenizer.from_pretrained(str(EN_ZH_DIR))
    model = MarianMTModel.from_pretrained(str(EN_ZH_DIR)).eval()
    return tok, model


@lru_cache(maxsize=1)
def _zh_wy():
    from transformers import AutoTokenizer, EncoderDecoderModel
    _ensure((ZH_WY_DIR,))
    tok = AutoTokenizer.from_pretrained(str(ZH_WY_DIR))
    model = EncoderDecoderModel.from_pretrained(str(ZH_WY_DIR)).eval()
    return tok, model


@lru_cache(maxsize=1)
def _zh_en():
    from transformers import MarianMTModel, MarianTokenizer
    _ensure((ZH_EN_DIR,))
    tok = MarianTokenizer.from_pretrained(str(ZH_EN_DIR))
    model = MarianMTModel.from_pretrained(str(ZH_EN_DIR)).eval()
    return tok, model


@lru_cache(maxsize=1)
def _wy_zh():
    from transformers import AutoTokenizer, EncoderDecoderModel
    _ensure((WY_ZH_DIR,))
    tok = AutoTokenizer.from_pretrained(str(WY_ZH_DIR))
    model = EncoderDecoderModel.from_pretrained(str(WY_ZH_DIR)).eval()
    return tok, model


@torch.no_grad()
def en_to_zh(text: str) -> str:
    if not text.strip():
        return text
    tok, model = _en_zh()
    enc = tok(text, return_tensors="pt", truncation=True, max_length=512)
    out = model.generate(**enc, max_length=512, num_beams=4)
    return tok.batch_decode(out, skip_special_tokens=True)[0]


@torch.no_grad()
def zh_to_wenyan(text: str) -> str:
    if not text.strip():
        return text
    tok, model = _zh_wy()
    enc = tok(text, return_tensors="pt", truncation=True,
              max_length=128, padding="max_length")
    out = model.generate(
        enc.input_ids,
        attention_mask=enc.attention_mask,
        num_beams=3, max_length=256,
        bos_token_id=101,
        eos_token_id=tok.sep_token_id,
        pad_token_id=tok.pad_token_id,
    )
    return tok.batch_decode(out, skip_special_tokens=True)[0]


@torch.no_grad()
def zh_to_en(text: str) -> str:
    if not text.strip():
        return text
    tok, model = _zh_en()
    enc = tok(text, return_tensors="pt", truncation=True, max_length=512)
    out = model.generate(**enc, max_length=512, num_beams=4)
    return tok.batch_decode(out, skip_special_tokens=True)[0]


@torch.no_grad()
def wenyan_to_zh(text: str) -> str:
    if not text.strip():
        return text
    tok, model = _wy_zh()
    enc = tok(text, return_tensors="pt", truncation=True,
              max_length=128, padding="max_length")
    out = model.generate(
        enc.input_ids,
        attention_mask=enc.attention_mask,
        num_beams=3, max_length=256,
        bos_token_id=101,
        eos_token_id=tok.sep_token_id,
        pad_token_id=tok.pad_token_id,
    )
    return tok.batch_decode(out, skip_special_tokens=True)[0]
