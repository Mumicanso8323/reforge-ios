#!/usr/bin/env python3
"""ストアの原稿(store/metadata・store/iap)の置き場が形どおりかを確かめる。

確かめるのは 6 つ。
1. 地域 5 つのフォルダと 6 ファイルがそろい、知らないファイルが無い。
2. 文字数の上限(末尾の改行 1 つは数えない)。
3. keywords.txt は ',' 区切りで、語の前後に空白も空の語も無い。
4. store/iap/ の品ごとに地域 5 つの JSON がそろい、キーは name と description だけ。上限つき。
5. --release のときだけ: name・subtitle・description・keywords と IAP の両方のキーが空でない。
6. en-US・ko の文にカナ・漢字が無く、中国語(両方)にカナが無い。

使い方: python3 tools/check-store-metadata.py [--release]   (外れがあれば終了コード 1)
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
META = ROOT / "store" / "metadata"
IAP = ROOT / "store" / "iap"
REGIONS = ["ja", "en-US", "zh-Hans", "zh-Hant", "ko"]
LIMITS = {"name": 30, "subtitle": 30, "keywords": 100, "promotional_text": 170,
          "description": 4000, "release_notes": 4000}
FILES = {f + ".txt" for f in LIMITS}
IAP_LIMITS = {"name": 30, "description": 45}
RELEASE_META = ["name", "subtitle", "description", "keywords"]
KANA = re.compile("[぀-ヿ]")
HAN = re.compile("[一-鿿]")

errors = []


def err(where, msg):
    errors.append(f"{where}: {msg}")


def rel(p):
    return p.relative_to(ROOT).as_posix()


def text_of(p):
    s = p.read_text(encoding="utf-8")
    return s[:-1] if s.endswith("\n") else s


def script_check(where, region, s):
    if region in ("en-US", "ko") and (KANA.search(s) or HAN.search(s)):
        err(where, "この言語の文にカナ・漢字がある")
    elif region in ("zh-Hans", "zh-Hant") and KANA.search(s):
        err(where, "中国語の文にカナがある")


def check_metadata(release):
    if not META.is_dir():
        err("store/metadata", "フォルダが無い")
        return
    for extra in sorted(p.name for p in META.iterdir() if p.name not in REGIONS):
        err(f"store/metadata/{extra}", "知らない地域のフォルダ(またはファイル)")
    for region in REGIONS:
        d = META / region
        if not d.is_dir():
            err(rel(d), "地域のフォルダが無い")
            continue
        present = {p.name for p in d.iterdir()}
        for missing in sorted(FILES - present):
            err(rel(d / missing), "ファイルが無い")
        for extra in sorted(present - FILES):
            err(rel(d / extra), "知らないファイル")
        for name in sorted(FILES & present):
            p = d / name
            key = name[:-4]
            s = text_of(p)
            if len(s) > LIMITS[key]:
                err(rel(p), f"文字数 {len(s)} が上限 {LIMITS[key]} を超えている")
            if key == "keywords" and s:
                for w in s.split(","):
                    if w == "":
                        err(rel(p), "空の語がある")
                    elif w != w.strip():
                        err(rel(p), f"語の前後に空白がある: {w!r}")
            if release and key in RELEASE_META and not s.strip():
                err(rel(p), "出す版では空にできない")
            script_check(rel(p), region, s)


def check_iap(release):
    if not IAP.is_dir():
        err("store/iap", "フォルダが無い")
        return 0
    products = sorted(p for p in IAP.iterdir() if p.is_dir())
    for prod in products:
        present = {p.name for p in prod.iterdir()}
        want = {r + ".json" for r in REGIONS}
        for missing in sorted(want - present):
            err(rel(prod / missing), "ファイルが無い")
        for extra in sorted(present - want):
            err(rel(prod / extra), "知らないファイル")
        for region in REGIONS:
            p = prod / (region + ".json")
            if not p.is_file():
                continue
            try:
                obj = json.loads(p.read_text(encoding="utf-8"))
            except ValueError as e:
                err(rel(p), f"JSON が読めない: {e}")
                continue
            if not isinstance(obj, dict) or set(obj) != set(IAP_LIMITS):
                err(rel(p), "キーは name と description だけにする")
                continue
            for k, lim in IAP_LIMITS.items():
                v = obj[k]
                if not isinstance(v, str):
                    err(rel(p), f"{k} が文字列でない")
                    continue
                if len(v) > lim:
                    err(rel(p), f"{k} の文字数 {len(v)} が上限 {lim} を超えている")
                if release and not v.strip():
                    err(rel(p), f"{k} が出す版では空にできない")
                script_check(f"{rel(p)}[{k}]", region, v)
    return len(products)


def main():
    release = "--release" in sys.argv[1:]
    check_metadata(release)
    n = check_iap(release)
    if errors:
        for e in errors:
            print(e)
        return 1
    print(f"ストアの原稿の置き場は形どおり(地域 {len(REGIONS)}・品 {n})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
