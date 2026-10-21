#!/usr/bin/env python3
"""アプリの画面のコード(ReForge/Sources の全部の .swift)に、「できない理由を説明する文」が書かれていないことを確かめる(INV-F1)。
押せない行動はボタンを置かず、理由の文でも補わない。見るのは 2 つ(禁止の語は同じ):
  - 画面の文字列リテラル(Text("…") と Text(verbatim: "…"))に、不足・禁止の語の形が無いこと。
  - ui("…") ・ UIText.shared.string("…") が引く文言の表(content/public/text/ja/)の日本語に、同じ語が無いこと(L-11:
    固定文言は表にあるので、ID を表の日本語に引いて照らす。表へ移したあとも、この規則は弱くならない)。"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
# 前は足元カード・暗い始まり・拠点のタブなど 5 本だけを見ていた。新しい画面のファイルも漏れないよう、全部を見る
FILES = [str(p.relative_to(ROOT)) for p in sorted((ROOT / "ReForge" / "Sources").rglob("*.swift"))]
FORBIDDEN = ["あと ", "あと\\(", "足りない", "がない", "できない", "遠すぎる", "届かない", "待つ"]
# 表の文では差し込みが {名前} の形。コードの補間の形(あと\()に当たる物
FORBIDDEN_IN_TABLE = FORBIDDEN + ["あと{"]
LITERAL = re.compile(r'Text\((?:verbatim: )?"([^"]*)"')
TABLE_ID = re.compile(r'(?<![\w.])(?:ui|UIText\.shared\.string)\(\s*"([^"]+)"')


def load_table(root):
    texts = {}
    for path in sorted((root / "content" / "public" / "text" / "ja").glob("*.json")):
        if not path.name.startswith("_"):
            texts.update(json.loads(path.read_text(encoding="utf-8")).get("texts", {}))
    return texts


def check(root=ROOT, files=FILES):
    table = load_table(root)
    bad = []
    for name in files:
        for number, line in enumerate((root / name).read_text(encoding="utf-8").splitlines(), 1):
            if line.lstrip().startswith("//"):
                continue
            for literal in LITERAL.findall(line):
                if any(word in literal for word in FORBIDDEN):
                    bad.append(f"{name}:{number}: {literal}")
            for identifier in TABLE_ID.findall(line):
                sentence = table.get(identifier, "")
                if any(word in sentence for word in FORBIDDEN_IN_TABLE):
                    bad.append(f"{name}:{number}: {identifier}: {sentence}")
    return bad


if __name__ == "__main__":
    bad = check()
    if bad:
        print("できない理由を説明する文が画面に書かれている(INV-F1):")
        print("\n".join(bad))
        sys.exit(1)
    print(f"アプリの画面のコード {len(FILES)} 本に、できない理由の文は無い")
