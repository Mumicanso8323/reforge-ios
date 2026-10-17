#!/usr/bin/env python3
"""部品(帯・札・パネル・タブ・ボタン)が暗い地のまま固定であることを確かめる(INV-O16・W-19)。
端末の外観(ライト/ダーク)にも時刻にも依らず同じ見え方にするため、次の 3 つを見る。
  (1) ReForgeApp.swift と SettingsCorner.swift に `.preferredColorScheme(.dark)` がある。
  (2) project.yml に `INFOPLIST_KEY_UIUserInterfaceStyle: Dark` がある(システムの警告・キーボードも暗くする)。
  (3) ReForge/Sources/ に、外観を読む `\\.colorScheme`・`userInterfaceStyle`・`traitCollection` が無い(`#if DEBUG` の中は除く)。
外れたらファイル:行を出して終了コード 1。python3 標準だけ。"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCHEME_FILES = ["ReForge/Sources/ReForgeApp.swift", "ReForge/Sources/Screens/SettingsCorner.swift"]
SCHEME = ".preferredColorScheme(.dark)"
PLIST_LINE = re.compile(r"^\s*INFOPLIST_KEY_UIUserInterfaceStyle:\s*\"?Dark\"?\s*$")
READS = re.compile(r"\.colorScheme|userInterfaceStyle|traitCollection")

problems: list[str] = []

# (1)
for name in SCHEME_FILES:
    path = ROOT / name
    if not path.exists():
        problems.append(f"{name}:1: ファイルが無い")
        continue
    if SCHEME not in path.read_text(encoding="utf-8"):
        problems.append(f"{name}:1: {SCHEME} が無い")

# (2)
project = ROOT / "project.yml"
lines = project.read_text(encoding="utf-8").splitlines()
if not any(PLIST_LINE.match(line) for line in lines):
    problems.append("project.yml:1: INFOPLIST_KEY_UIUserInterfaceStyle: Dark が無い")

# (3) #if DEBUG の中(#else の手前まで)は除く。入れ子の #if は深さで数える。
for path in sorted((ROOT / "ReForge/Sources").rglob("*.swift")):
    rel = path.relative_to(ROOT).as_posix()
    stack: list[bool] = []  # 各 #if が「DEBUG の中」か
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("#if"):
            stack.append(stripped.replace(" ", "") == "#ifDEBUG")
        elif stripped.startswith("#else") or stripped.startswith("#elseif"):
            if stack:
                stack[-1] = False
        elif stripped.startswith("#endif"):
            if stack:
                stack.pop()
        elif not stripped.startswith("//") and not any(stack) and READS.search(line):
            problems.append(f"{rel}:{number}: 外観を読んでいる: {stripped}")

if problems:
    print("部品が暗い地のまま固定になっていない(INV-O16):")
    print("\n".join(problems))
    sys.exit(1)
print("部品は暗い地のまま固定(preferredColorScheme・Info.plist・外観の読み無し)")
