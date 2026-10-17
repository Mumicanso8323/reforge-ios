#!/usr/bin/env python3
"""アプリが OS に知らせる言語が、出す言語(LanguageID.released)+ Base と一致していることを確かめる(L-11・BRK-23)。

XcodeGen には knownRegions という設定の鍵が無い。プロジェクトの knownRegions は XcodeGen が次の和集合で作る
(XcodeGen の PBXProjGenerator・SourceGenerator のソースで確かめた):
  - options.developmentLanguage(project.yml。既定 en)
  - Base(options.useBaseInternationalization が false でなければ。既定 true)
  - ソースの中の *.lproj の名前
  - ソースの中の文字列カタログ(*.xcstrings)の localizations にある言語(sourceLanguage は数えない)
この道具はその和集合を同じ決まりで作り、出す言語 + Base と照らす(多くても少なくても失敗)。
Xcode は knownRegions から Info.plist の CFBundleLocalizations を作るので、OS の「設定 > このアプリ」の言語の一覧は
ここで決まる。`INFOPLIST_KEY_CFBundleLocalizations` のような生成の対象でない鍵は黙って捨てられるので、書いたら失敗にする。
ほかに ReForge/Resources/InfoPlist.xcstrings の言語の項が出す言語だけであること、CFBundleDisplayName を持つことも確かめる。

使い方: python3 tools/check-languages.py   (外れたら終了コード 1)
"""
import argparse
import importlib.util
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCE_DIRS = ["ReForge", "ReForgeTests", "ReForgeUITests"]  # project.yml の targets の sources
INFO_PLIST_CATALOG = "ReForge/Resources/InfoPlist.xcstrings"


def released_languages(root):
    spec = importlib.util.spec_from_file_location("released_languages", HERE / "released-languages.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.released_languages((root / "ReForgeCore/Sources/RFKernel/Text.swift").read_text(encoding="utf-8"))


def uncommented_lines(text):
    return [line.split(" #")[0] for line in text.splitlines() if not line.lstrip().startswith("#")]


def catalog_locales(path):
    """XcodeGen と同じ: strings の各項目の localizations のキーの和集合。"""
    data = json.loads(path.read_text(encoding="utf-8"))
    found = set()
    for item in data.get("strings", {}).values():
        found |= set((item.get("localizations") or {}).keys())
    return found


def known_regions(root):
    lines = uncommented_lines((root / "project.yml").read_text(encoding="utf-8"))
    development = "en"
    base = True
    for line in lines:
        match = re.match(r"\s*developmentLanguage:\s*\"?([\w-]+)\"?\s*$", line)
        if match:
            development = match.group(1)
        if re.match(r"\s*useBaseInternationalization:\s*(false|no)\b", line):
            base = False
    regions = {development}
    if base:
        regions.add("Base")
    for name in SOURCE_DIRS:
        directory = root / name
        if not directory.exists():
            continue
        for path in directory.rglob("*"):
            if path.is_dir() and path.suffix == ".lproj":
                regions.add(path.stem)
            elif path.is_file() and path.suffix == ".xcstrings":
                regions |= catalog_locales(path)
    return regions


def check(root):
    problems = []
    released = set(released_languages(root))
    expected = released | {"Base"}
    project = (root / "project.yml").read_text(encoding="utf-8")
    for line in uncommented_lines(project):
        if re.search(r"\bknownRegions\b", line) or "INFOPLIST_KEY_CFBundleLocalizations" in line:
            problems.append("project.yml に XcodeGen が読まない鍵がある(knownRegions・INFOPLIST_KEY_CFBundleLocalizations は無効。"
                            "言語は developmentLanguage と文字列カタログの項で決まる)")
    regions = known_regions(root)
    if regions != expected:
        problems.append(f"プロジェクトの knownRegions {sorted(regions)} が 出す言語 + Base {sorted(expected)} と違う"
                        f"(多い: {sorted(regions - expected)}・足りない: {sorted(expected - regions)})")
    catalog = root / INFO_PLIST_CATALOG
    if not catalog.exists():
        problems.append(f"{INFO_PLIST_CATALOG} が無い")
    else:
        locales = catalog_locales(catalog)
        if locales != released:
            problems.append(f"{INFO_PLIST_CATALOG} の言語の項 {sorted(locales)} が 出す言語 {sorted(released)} と違う")
        if "CFBundleDisplayName" not in json.loads(catalog.read_text(encoding="utf-8")).get("strings", {}):
            problems.append(f"{INFO_PLIST_CATALOG} に CFBundleDisplayName が無い")
    return problems


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=HERE.parent)
    args = parser.parse_args(argv)
    problems = check(args.root.resolve())
    if problems:
        print("アプリの言語が出す言語と合っていない:")
        for problem in problems:
            print(f"  {problem}")
        return 1
    print("アプリの言語は出す言語 + Base と合っている")
    return 0


if __name__ == "__main__":
    sys.exit(main())
