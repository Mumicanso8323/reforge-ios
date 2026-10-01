#!/usr/bin/env python3
"""アプリ(ReForge/)と本体(ReForgeEngine が見せる全モジュール)の型の名前がぶつからないかを静的に確かめる。

アプリは Linux でコンパイルされないので、本体に public な型を足して名前がアプリの型と重なると、
iOS のジョブで初めて「'X' is ambiguous」で落ちる(93867cf の FileSaveStorage)。確かめるのは 3 つ。
1. アプリが定義する型の名前と、本体の public な型の名前の重なり。
2. 本体の中で、ReForgeEngine が見せる別々のモジュールが同じ名前の public な型を持つこと
   (アプリから見ると同じく曖昧になる)。
3. 本体の public な型の名前が SwiftUI・Foundation などの型と同じで、アプリがその名前を
   モジュール名を付けずに使っていること。

型の宣言は「ファイルの一番外の段」のものだけを見る(入れ子の型は外の型の名前で区別されるので重ならない)。
使い方: python3 tools/check-app-names.py   (重なりがあれば終了コード 1)
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CORE = ROOT / "ReForgeCore" / "Sources"
UMBRELLA = CORE / "ReForgeEngine"
APPS = [ROOT / "ReForge", ROOT / "ReForgeTests"]

DECL = re.compile(r"^((?:@\w+(?:\([^)]*\))?\s+)*)((?:(?:public|open|internal|fileprivate|private|final|indirect)\s+)*)"
                  r"(struct|class|enum|protocol|typealias|actor)\s+(\w+)", re.M)

# アプリが import する Apple のモジュールの、よく使う型の名前(本体に同じ名前があると、裸で使うと曖昧になる)
APPLE_NAMES = {
    # SwiftUI
    "View", "Text", "Image", "Color", "Font", "Shape", "Path", "Label", "Button", "Group", "Section", "List",
    "Canvas", "Layout", "Animation", "Transaction", "Binding", "State", "Environment", "Scene", "App", "Window",
    "Gesture", "Alignment", "Edge", "Axis", "Angle", "Anchor", "Spacer", "Divider", "Toggle", "Picker", "Slider",
    "Stepper", "Menu", "Link", "Grid", "GridItem", "Table", "Form", "Material", "Gradient", "Namespace",
    "GraphicsContext", "Shading", "StrokeStyle", "FillStyle", "Visibility", "Tab", "Sheet",
    # Foundation など
    "Data", "Date", "URL", "UUID", "Locale", "Calendar", "TimeZone", "Bundle", "Notification", "Timer",
    "Process", "Operation", "Measurement", "Unit", "Decimal", "IndexSet", "CharacterSet", "Progress",
    "Logger", "Task", "Result", "Duration", "Clock",
}


def strip(s: str) -> str:
    s = re.sub(r"/\*.*?\*/", "", s, flags=re.S)
    s = re.sub(r'"""(?:.|\n)*?"""', '""', s)
    s = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', s)
    return re.sub(r"//[^\n]*", "", s)


def top_level_text(s: str) -> str:
    """中括弧の外(深さ 0)の文字だけを残す(行の位置は保つ)。"""
    out, depth = [], 0
    for ch in s:
        if ch == "{":
            depth += 1
            out.append(" ")
        elif ch == "}":
            depth -= 1
            out.append(" ")
        elif depth == 0 or ch == "\n":
            out.append(ch)
        else:
            out.append(" ")
    return "".join(out)


def decls(f: pathlib.Path, public_only: bool):
    s = top_level_text(strip(f.read_text(encoding="utf-8")))
    for m in DECL.finditer(s):
        mods = m.group(2).split()
        if public_only and not ({"public", "open"} & set(mods)):
            continue
        yield m.group(4), s.count("\n", 0, m.start()) + 1


def exported_modules() -> list:
    mods = []
    for f in UMBRELLA.glob("*.swift"):
        mods += re.findall(r"@_exported\s+import\s+(\w+)", f.read_text(encoding="utf-8"))
    return sorted(set(mods))


def main() -> int:
    core = {}  # 名前 → [(モジュール, 場所)]
    for mod in exported_modules():
        for f in sorted((CORE / mod).rglob("*.swift")):
            for name, line in decls(f, public_only=True):
                core.setdefault(name, []).append((mod, f"{f.relative_to(ROOT)}:{line}"))
    problems = []

    for name, places in sorted(core.items()):
        mods = sorted({m for m, _ in places})
        if len(mods) > 1:
            problems.append(f"本体の public な型 {name} が複数のモジュールにある({', '.join(p for _, p in places)})")

    app_files = [f for base in APPS if base.exists() for f in sorted(base.rglob("*.swift"))]
    for f in app_files:
        for name, line in decls(f, public_only=False):
            if name in core:
                problems.append(f"{f.relative_to(ROOT)}:{line}: アプリの型 {name} が本体の public な型"
                                f"({core[name][0][1]})と同じ名前")

    clash = sorted(APPLE_NAMES & set(core))
    for f in app_files:
        body = strip(f.read_text(encoding="utf-8"))
        for name in clash:
            # モジュール名やドットを付けずに型として使っている所(SwiftUI.Shape・x.Shape・.Shape は除く)
            for m in re.finditer(rf"(?<![\w.]){name}\b(?!\s*:)", body):
                line = body.count("\n", 0, m.start()) + 1
                problems.append(f"{f.relative_to(ROOT)}:{line}: {name} は本体({core[name][0][1]})と Apple の"
                                f"モジュールの両方にある。モジュール名を付けて書く(例 SwiftUI.{name})")
                break

    for p in problems:
        print(p)
    if problems:
        print(f"型の名前の重なりが {len(problems)} 件(アプリは Linux でコンパイルされないので、ここで直す)")
        return 1
    print(f"型の名前の重なりは無い(本体の public な型 {len(core)}・アプリのファイル {len(app_files)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
