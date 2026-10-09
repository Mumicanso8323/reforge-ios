#!/usr/bin/env python3
"""足元カード・暗い始まり・拠点のタブの画面コードに、「できない理由を説明する文」が書かれていないことを確かめる(INV-F1)。
押せない行動はボタンを置かず、理由の文でも補わない。画面の文字列リテラル(Text("…"))に、不足・禁止の語の形が無いこと。"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
FILES = ["ReForge/Sources/Game/FootCardView.swift", "ReForge/Sources/Game/DarkStartScene.swift", "ReForge/Sources/Game/Tabs/BaseTab.swift"]
FORBIDDEN = ["あと ", "あと\\(", "足りない", "がない", "できない", "遠すぎる", "届かない", "待つ"]
LITERAL = re.compile(r'Text\((?:verbatim: )?"([^"]*)"')

bad = []
for name in FILES:
    for number, line in enumerate((ROOT / name).read_text(encoding="utf-8").splitlines(), 1):
        if line.lstrip().startswith("//"):
            continue
        for literal in LITERAL.findall(line):
            if any(word in literal for word in FORBIDDEN):
                bad.append(f"{name}:{number}: {literal}")
if bad:
    print("できない理由を説明する文が画面に書かれている(INV-F1):")
    print("\n".join(bad))
    sys.exit(1)
print("足元カード・暗い始まり・拠点のタブに、できない理由の文は無い")
