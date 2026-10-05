#!/usr/bin/env python3
"""Release(TestFlight・店に出す組み)に、開発・撮影・台本流し込みの物が入らないことを静的に確かめる。

1. ReForge/Sources/Debug/ の各ファイルは、全体が `#if DEBUG ... #endif` で囲まれている。
2. DEBUG だけのファイル(上の Debug/ と、全体が #if DEBUG の物)が宣言する型・撮影の起動引数の文字列は、
   それ以外の場所では `#if DEBUG` の中(#else は除く)でしか使わない。
3. `REFORGE_DEV` を条件に使う `#if` は `DEBUG || REFORGE_DEV` の形だけ(dev の ipa のジョブだけが値を渡す)。
4. ci.yml の testflight ジョブは SWIFT_ACTIVE_COMPILATION_CONDITIONS / DEV_IPA_CONDITIONS / REFORGE_DEV を持たない。
   (組んだ .app のバイナリに debug 専用の文字列が無いことの確かめは、testflight ジョブの中で strings で行う。)

使い方: python3 tools/check-release-build.py   (違反があれば終了コード 1)
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "ReForge" / "Sources"
CI = ROOT / ".github" / "workflows" / "ci.yml"
DEBUG_STRINGS = ["ReForgeReplay", "ReForgeScreenshot"]

errors = []


def strip(s: str) -> str:
    """コメントを消す(行数は保つ)。文字列の中身は残す(起動引数の検査のため)。"""
    s = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), s, flags=re.S)
    return re.sub(r"//[^\n]*", "", s)


def scan(text: str):
    """各行が「DEBUG の #if の中(#else でない側)」かの一覧と、#if / #elseif の条件の一覧 [(行, 条件)]。"""
    stack = []  # [条件, else 側か]
    flags, conds = [], []
    for no, line in enumerate(text.split("\n"), 1):
        m = re.match(r"#(if|elseif|else|endif)\b\s*(.*)", line.strip())
        if m:
            kw, cond = m.group(1), m.group(2).strip()
            if kw == "if":
                stack.append([cond, False])
                conds.append((no, cond))
            elif kw == "elseif" and stack:
                stack[-1] = [cond, True]
                conds.append((no, cond))
            elif kw == "else" and stack:
                stack[-1][1] = True
            elif kw == "endif" and stack:
                stack.pop()
        flags.append(any(c == "DEBUG" and not e for c, e in stack))
    return flags, conds


files = {f: f.read_text(encoding="utf-8") for f in sorted(SRC.rglob("*.swift"))}
debug_files = set()
for f, raw in files.items():
    body = [l.strip() for l in strip(raw).split("\n") if l.strip() and not l.strip().startswith("import ")]
    whole = bool(body) and body[0] == "#if DEBUG" and body[-1] == "#endif" and body.count("#if DEBUG") == 1
    if f.parent.name == "Debug" and not whole:
        errors.append(f"{f.relative_to(ROOT)}: Debug/ のファイルが全体を #if DEBUG ... #endif で囲んでいない")
    if whole:
        debug_files.add(f)

names = set()
for f in debug_files:
    for m in re.finditer(r"\b(?:struct|class|enum|actor|protocol|typealias)\s+(\w+)", strip(files[f])):
        names.add(m.group(1))
# 他のファイルでも宣言される名前(同名の型)は、取り違えるので対象から外す
for f, raw in files.items():
    if f not in debug_files:
        for m in re.finditer(r"\b(?:struct|class|enum|actor|protocol|typealias)\s+(\w+)", strip(raw)):
            names.discard(m.group(1))

pats = [(n, re.compile(r"\b" + re.escape(n) + r"\b")) for n in sorted(names)]
pats += [(s, re.compile(re.escape(s))) for s in DEBUG_STRINGS]

for f, raw in files.items():
    rel = f.relative_to(ROOT)
    lines = strip(raw).split("\n")
    flags, conds = scan("\n".join(lines))
    for no, cond in conds:
        if "REFORGE_DEV" in cond and cond.replace(" ", "") != "DEBUG||REFORGE_DEV":
            errors.append(f"{rel}:{no}: REFORGE_DEV の #if は `DEBUG || REFORGE_DEV` の形だけにする(今: {cond})")
    if f in debug_files:
        continue
    for i, line in enumerate(lines):
        if line.strip().startswith("#"):
            continue
        for n, p in pats:
            if p.search(line) and not flags[i]:
                errors.append(f"{rel}:{i + 1}: DEBUG だけの `{n}` が #if DEBUG の外にある")

# ci.yml: testflight ジョブに dev の切り替えが無い
if CI.exists():
    ci = CI.read_text(encoding="utf-8")
    m = re.search(r"^  testflight:\n(.*?)(?=^  \w[\w-]*:\n|\Z)", ci, flags=re.S | re.M)
    if m:
        for bad in ("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "DEV_IPA_CONDITIONS", "REFORGE_DEV"):
            if bad in m.group(1):
                errors.append(f".github/workflows/ci.yml: testflight ジョブに {bad} がある")
    else:
        errors.append(".github/workflows/ci.yml: testflight ジョブが無い")

if errors:
    print("\n".join(errors))
    print(f"Release の組みの確かめに {len(errors)} 件の違反")
    sys.exit(1)
print(f"Release の組みに debug の物は入らない(DEBUG だけのファイル {len(debug_files)} 本・型 {len(names)} 個を確かめた)")
