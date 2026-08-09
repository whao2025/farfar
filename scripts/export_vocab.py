#!/usr/bin/env python3
"""从 albert_finetuned/tokenizer.json 按 id 升序导出 vocab.txt（行号即 token id）。"""
import json
import sys

SRC = r"D:\freepdf\models\albert_finetuned\tokenizer.json"
OUT = r"D:\freepdf\models\vocab.txt"

with open(SRC, encoding="utf-8") as f:
    tj = json.load(f)

vocab = tj["model"]["vocab"]
n = len(vocab)
items = sorted(vocab.items(), key=lambda kv: kv[1])

# 硬断言：id 必须连续 0..n-1，不存在则报错
ids = [v for _, v in items]
assert ids == list(range(n)), f"vocab ids not contiguous 0..{n-1}"

lines = [t for t, _ in items]
with open(OUT, "w", encoding="utf-8") as f:
    for line in lines:
        f.write(f"{line}\n")

# 自检
pad = vocab.get("[PAD]"); unk = vocab.get("[UNK]")
cls = vocab.get("[CLS]"); sep = vocab.get("[SEP]")
print(f"exported {n} tokens -> {OUT}")
print(f"[PAD]={pad} [UNK]={unk} [CLS]={cls} [SEP]={sep} (file line 0-based ids)")