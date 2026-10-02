#!/usr/bin/env python3
"""画面の写真の結果(xcresult から出した添付)を、artifact に上げる形に整える(CI の screens ジョブ)。

  xcrun xcresulttool export attachments --path screens.xcresult --output-path screens-raw/   (Xcode 16 以降)
  python3 tools/collect-screens.py screens-raw screens --device "iPhone 17"

出すもの(artifact に上げるのはこの 2 種だけ。ログは上げない):
  screens/<言語>_<画面>.png   … 60 枚(ja_map.png … ko_bootFailure.png)
  screens/report.json         … 検査に当たった要素(言語・画面・要素の識別子・種類・大きさ)と、撮れた枚数

export attachments は manifest.json(各添付の exportedFileName と suggestedHumanReadableName)と、UUID 名のファイルを出す。
suggestedHumanReadableName は「<添付の名前>_<連番>_<UUID>.<拡張子>」の形なので、連番と UUID を落として元の名前に戻す。
撮れた PNG が期待の 60 枚に満たなければ終了コード 1(失敗してもテスト側の結果は別に出る)。
"""
import argparse
import json
import pathlib
import re
import shutil
import sys

LANGS = ["ja", "en", "zh-Hans", "zh-Hant", "ko"]
SCREENS = ["map", "foot", "design", "base", "crew", "research", "gameOver", "settings",
           "title", "notes", "decisionBand", "bootFailure"]
SUFFIX = re.compile(r"^(?P<name>.+?)_\d+_[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}(?P<ext>\.[A-Za-z0-9]+)?$")


def base_name(human: str, exported: str) -> tuple:
    """(添付の名前, 拡張子)。"""
    m = SUFFIX.match(human)
    if m:
        return m.group("name"), m.group("ext") or pathlib.Path(exported).suffix
    p = pathlib.Path(human)
    return (p.stem, p.suffix or pathlib.Path(exported).suffix) if p.suffix else (human, pathlib.Path(exported).suffix)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("raw")
    ap.add_argument("out")
    ap.add_argument("--device", default="")
    a = ap.parse_args()
    raw, out = pathlib.Path(a.raw), pathlib.Path(a.out)
    out.mkdir(parents=True, exist_ok=True)

    manifest_path = raw / "manifest.json"
    if not manifest_path.exists():
        print("manifest.json が無い(xcresulttool の出力が空)", file=sys.stderr)
        manifest = []
    else:
        manifest = json.loads(manifest_path.read_text())

    pngs, reports = {}, []
    for test in manifest:
        for att in test.get("attachments", []):
            exported = att.get("exportedFileName", "")
            src = raw / exported
            if not exported or not src.exists():
                continue
            name, ext = base_name(att.get("suggestedHumanReadableName", exported), exported)
            if name.startswith("report_"):
                try:
                    reports.append(json.loads(src.read_text()))
                except ValueError:
                    print(f"{name}: JSON を読めない", file=sys.stderr)
            elif ext.lower() == ".png":
                shutil.copyfile(src, out / f"{name}.png")
                pngs[name] = True

    expected = [f"{lang}_{screen}" for lang in LANGS for screen in SCREENS]
    missing = [n for n in expected if n not in pngs]
    findings = [f for r in reports for f in r.get("findings", [])]
    # 画面ごとの行(offscreen から外した幅か高さ 1pt 以下の要素の数と、研究の節の有無。後で増えたら気づくため)
    rows = sorted(
        ({"language": r.get("language", ""), "screen": r.get("screen", ""),
          "ignoredZeroSize": r.get("ignoredZeroSize", 0), **({"research": r["research"]} if r.get("research") else {})}
         for r in reports),
        key=lambda r: (r["language"], r["screen"]))
    report = {
        "device": a.device,
        "expected": len(expected),
        "shots": len([n for n in expected if n in pngs]),
        "missing": missing,
        "screens": rows,
        "findings": sorted(findings, key=lambda f: (f["language"], f["screen"], f["kind"], f["id"])),
    }
    (out / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    empty = [f"{r['language']}_{r['screen']}" for r in rows if r.get("research") == "empty"]
    if empty:
        print("research: empty " + ", ".join(empty))
    print(f"撮れた {report['shots']}/{report['expected']} 枚・検査に当たった {len(findings)} 件")
    for f in report["findings"][:40]:
        print(f"  {f['language']}_{f['screen']}: {f['kind']} {f['id']} {f['detail']}")
    if missing:
        print("撮れていない: " + ", ".join(missing[:10]) + (" …" if len(missing) > 10 else ""))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
