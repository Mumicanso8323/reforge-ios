#!/usr/bin/env python3
"""画面の写真の結果(xcresult から出した添付)を、artifact に上げる形に整える(CI の screens ジョブ)。

  xcrun xcresulttool export attachments --path screens.xcresult --output-path screens-raw/   (Xcode 16 以降)
  python3 tools/collect-screens.py screens-raw screens --device "iPhone 17"

出すもの(artifact に上げるのはこの 2 種だけ。ログは上げない):
  screens/<言語>_<画面>.png   … 60 枚(ja_map.png … ko_bootFailure.png)
  screens/pseudo_<画面>.png   … 擬似言語の写真(L-13。上の 60 枚には足さない別の組)
  screens/report.json         … 検査に当たった要素(言語・画面・要素の識別子・種類・大きさ)と、撮れた枚数
  screens/time_<点>_<外観>.png … 時刻の色の写真 8 枚(4 点 × ダーク/ライト。W-19。--time-raw の添付から。上の 60 枚の数え方とは別)
  screens/time-report.json    … 添付 timehash_<点>_<外観>(JSON)を集めたもの。tools/check-time-tint-shots.py が判定する

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
TIME_POINTS = ["dawn", "noon", "evening", "night"]
APPEARANCES = ["dark", "light"]
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
    # 時刻の色の写真は別の xcresult(外観ごと)に入る。その取り出し先(何度でも指定できる)
    ap.add_argument("--time-raw", action="append", default=[])
    a = ap.parse_args()
    raw, out = pathlib.Path(a.raw), pathlib.Path(a.out)
    out.mkdir(parents=True, exist_ok=True)

    manifests = []
    for directory in [raw] + [pathlib.Path(d) for d in a.time_raw]:
        manifest_path = directory / "manifest.json"
        if not manifest_path.exists():
            print(f"{manifest_path} が無い(xcresulttool の出力が空)", file=sys.stderr)
            continue
        manifests.append((directory, json.loads(manifest_path.read_text())))

    pngs, reports, time_hashes = {}, [], []
    for directory, manifest in manifests:
        for test in manifest:
            for att in test.get("attachments", []):
                exported = att.get("exportedFileName", "")
                src = directory / exported
                if not exported or not src.exists():
                    continue
                name, ext = base_name(att.get("suggestedHumanReadableName", exported), exported)
                if name.startswith("report_"):
                    try:
                        reports.append(json.loads(src.read_text()))
                    except ValueError:
                        print(f"{name}: JSON を読めない", file=sys.stderr)
                elif name.startswith("timehash_"):
                    try:
                        time_hashes.append(json.loads(src.read_text()))
                    except ValueError:
                        print(f"{name}: JSON を読めない", file=sys.stderr)
                elif ext.lower() == ".png":
                    shutil.copyfile(src, out / f"{name}.png")
                    pngs[name] = True

    expected = [f"{lang}_{screen}" for lang in LANGS for screen in SCREENS]
    missing = [n for n in expected if n not in pngs]
    findings = [f for r in reports for f in r.get("findings", [])]
    # 擬似言語の写真(L-13。pseudo_<画面>.png)は期待の枚数に足さない別の組。縮める・切る区分の切れは報告に載せるだけ
    pseudo_shots = sorted(n for n in pngs if n.startswith("pseudo_"))
    pseudo_reported = [f for r in reports for f in r.get("reported", [])]
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
        "pseudoShots": len(pseudo_shots),
        "pseudoReported": sorted(pseudo_reported, key=lambda f: (f["screen"], f["id"])),
        "findings": sorted(findings, key=lambda f: (f["language"], f["screen"], f["kind"], f["id"])),
    }
    (out / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    empty = [f"{r['language']}_{r['screen']}" for r in rows if r.get("research") == "empty"]
    if empty:
        print("research: empty " + ", ".join(empty))
    print(f"撮れた {report['shots']}/{report['expected']} 枚・検査に当たった {len(findings)} 件")
    print(f"擬似言語の写真 {len(pseudo_shots)} 枚・縮める/切る区分の切れの報告 {len(pseudo_reported)} 件(失敗にしない)")
    for f in report["findings"][:40]:
        print(f"  {f['language']}_{f['screen']}: {f['kind']} {f['id']} {f['detail']}")
    # 時刻の色の写真: time_*.png 8 枚(4 点 × 2 外観)。--time-raw を渡したときだけ見る(今の 60 枚の数え方は変えない)
    time_missing = []
    if a.time_raw:
        time_missing = [f"time_{p}_{look}" for p in TIME_POINTS for look in APPEARANCES if f"time_{p}_{look}" not in pngs]
        time_hashes.sort(key=lambda h: (h.get("point", ""), h.get("appearance", "")))
        (out / "time-report.json").write_text(json.dumps(time_hashes, ensure_ascii=False, indent=2) + "\n")
        print(f"時刻の色の写真 {8 - len(time_missing)}/8 枚・要約 {len(time_hashes)} 件")
        if time_missing:
            print("時刻の色の写真が撮れていない: " + ", ".join(time_missing))
    if missing:
        print("撮れていない: " + ", ".join(missing[:10]) + (" …" if len(missing) > 10 else ""))
    return 1 if (missing or time_missing) else 0


if __name__ == "__main__":
    sys.exit(main())
