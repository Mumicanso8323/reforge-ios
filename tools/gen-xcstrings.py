#!/usr/bin/env python3
"""ReForge/Sources の画面の固定文言(かな・漢字・ハングルを含む文字列リテラル。Text(verbatim:) は除く)から
Localizable.xcstrings を作り直す。

規約(F §4・多言語):
- 画面の固定文言は `Text("…")` で書く。リテラルが文字列カタログのキーになる。
- 数や名前の入る文は SwiftUI の補間をそのままキーにする(`Text("建造中 \\(p)%")`)。補間に入れてよいのは
  整数(カタログでは %lld)と、本体がその言語で組んだ名前の文字列(%@)だけ。
  型は道具から見えないので、次の規則で決める:
    - 既定は %lld(整数)
    - 文字列を入れる行は、行の末尾に `// xcstrings: @,lld` のように補間の順に型を書く(@ = 文字列、lld = 整数)
  キーは Xcode が作るものと同じ形(補間の位置に %lld・%@、% は %%)。
- 固定文言を `Text(verbatim:)`・連結で組まない。

使い方:
  python3 tools/gen-xcstrings.py           カタログを作り直す(既存の訳は残す)
  python3 tools/gen-xcstrings.py --check   作り直すと変わるなら終了コード 1(CI 用)
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "ReForge" / "Sources"
OUT = ROOT / "ReForge" / "Resources" / "Localizable.xcstrings"
LITERAL = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
TYPES = re.compile(r'//\s*xcstrings:\s*([@a-z, ]+)')


def interpolations(text):
    """リテラルの中の \\( … \\) を、入れ子の括弧を数えて取り出す。[(開始, 終了)]"""
    out, i = [], 0
    while True:
        j = text.find("\\(", i)
        if j < 0:
            return out
        depth, k = 1, j + 2
        while k < len(text) and depth:
            depth += {"(": 1, ")": -1}.get(text[k], 0)
            k += 1
        out.append((j, k))
        i = k


def is_word(ch):
    """訳す文字(かな・漢字・ハングル)。罫線・矢印・全角の記号だけの文字列はカタログに入れない。"""
    o = ord(ch)
    return (0x3040 <= o <= 0x30FF) or (0x3400 <= o <= 0x9FFF) or (0xAC00 <= o <= 0xD7AF) or (0xF900 <= o <= 0xFAFF)


def strip_interpolations(text):
    out, last = "", 0
    for a, b in interpolations(text):
        out += text[last:a]
        last = b
    return out + text[last:]


def to_key(text, types):
    spans = interpolations(text)
    if len(types) not in (0, len(spans)):
        raise SystemExit(f"xcstrings: の型の数({len(types)})が補間の数({len(spans)})と違う: {text}")
    key, last = "", 0
    for n, (a, b) in enumerate(spans):
        key += text[last:a].replace("%", "%%")
        t = types[n] if types else "lld"
        key += "%@" if t == "@" else "%lld"
        last = b
    key += text[last:].replace("%", "%%")
    # Swift のエスケープ(\" \\)を戻す
    return key.replace('\\"', '"').replace("\\\\", "\\")


def literals():
    found = set()
    for path in sorted(SOURCES.rglob("*.swift")):
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.strip().startswith("//"):
                continue
            m = TYPES.search(line)
            types = [t.strip() for t in m.group(1).split(",")] if m else []
            code = line.split("//")[0] if not m else line[:m.start()]
            for lit in LITERAL.finditer(code):
                text = lit.group(1)
                if code[:lit.start()].rstrip().endswith("verbatim:"):
                    continue  # Text(verbatim:) は訳さない(記号と本体で組んだ名前だけの行)
                if any(is_word(ch) for ch in strip_interpolations(text)):
                    found.add(to_key(text, types) if "\\(" in text else text.replace('\\"', '"'))
    return sorted(found)


def main():
    old = {}
    if OUT.exists():
        old = json.loads(OUT.read_text(encoding="utf-8")).get("strings", {})
    strings = {}
    for key in literals():
        entry = old.get(key) or {}
        locs = dict(entry.get("localizations") or {})
        locs["ja"] = {"stringUnit": {"state": "translated", "value": key}}
        strings[key] = {**entry, "localizations": locs}
    catalog = {"sourceLanguage": "ja", "strings": strings, "version": "1.0"}
    text = json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if "--check" in sys.argv[1:]:
        if not OUT.exists() or OUT.read_text(encoding="utf-8") != text:
            print("Localizable.xcstrings が画面の文言と合っていない(python3 tools/gen-xcstrings.py で作り直す)")
            return 1
        print(f"Localizable.xcstrings は画面の文言と合っている({len(strings)} 件)")
        return 0
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(text, encoding="utf-8")
    print(f"{OUT.relative_to(ROOT)}: {len(strings)} 件")
    return 0


if __name__ == "__main__":
    sys.exit(main())
