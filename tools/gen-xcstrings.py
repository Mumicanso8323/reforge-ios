#!/usr/bin/env python3
"""ReForge/Sources の画面の固定文言(日本語を含む文字列リテラル)から Localizable.xcstrings を作り直す。

規約: 画面の文言は補間なしのリテラルで書く(数や名前が入る文は ReForgeCore の GameText で組み立て、
Text(verbatim:) で出す)。こうするとリテラル = 文字列カタログのキーになり、Linux の swift test(TEST-08)
で「全文言がカタログにある」「禁止語が無い」を機械的に確かめられる。

使い方: python3 tools/gen-xcstrings.py   (リポジトリのルートで)
"""
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "ReForge" / "Sources"
OUT = ROOT / "ReForge" / "Resources" / "Localizable.xcstrings"
LITERAL = re.compile(r'"((?:[^"\\\n]|\\.)*)"')


def literals():
    found = set()
    for path in sorted(SOURCES.rglob("*.swift")):
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.strip().startswith("//"):
                continue
            for m in LITERAL.finditer(line):
                text = m.group(1)
                if any(ord(ch) > 127 for ch in text):
                    found.add(text)
    return sorted(found)


def main():
    strings = {
        key: {"localizations": {"ja": {"stringUnit": {"state": "translated", "value": key}}}}
        for key in literals()
    }
    catalog = {"sourceLanguage": "ja", "strings": strings, "version": "1.0"}
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"{OUT.relative_to(ROOT)}: {len(strings)} 件")


if __name__ == "__main__":
    main()
