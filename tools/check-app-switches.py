#!/usr/bin/env python3
"""アプリ(ReForge/)の switch が、本体(ReForgeCore/Sources)の enum を網羅しているかを静的に確かめる。

アプリの側は Linux の swift test ではコンパイルされないので、本体の enum に case を足すと、
アプリの switch が気づかれないまま壊れる(iOS の CI で初めて落ちる)。統合のたびに回す。

やり方(Swift を解析しない近似):
1. 本体の enum を全部読み、enum の名前 → case の名前の集合を作る。
2. アプリの各 switch の中括弧の中から `case .名前` を集める(default / @unknown default があれば飛ばす)。
3. その case の名前を全部持つ本体の enum を候補とし、候補のどれにも足りない case があれば知らせる。
   候補が無い(アプリ側の enum・文字列など)switch は見ない。

使い方: python3 tools/check-app-switches.py   (網羅でない switch があれば終了コード 1)
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CORE = ROOT / "ReForgeCore" / "Sources"
APPS = [ROOT / "ReForge", ROOT / "ReForgeTests"]


def strip_comments(s: str) -> str:
    s = re.sub(r"/\*.*?\*/", "", s, flags=re.S)
    s = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', s)
    return re.sub(r"//[^\n]*", "", s)


def block_after(s: str, start: int) -> str:
    """start 以降の最初の { から対応する } までの中身。"""
    i = s.find("{", start)
    if i < 0:
        return ""
    depth = 0
    for j in range(i, len(s)):
        if s[j] == "{":
            depth += 1
        elif s[j] == "}":
            depth -= 1
            if depth == 0:
                return s[i + 1:j]
    return s[i + 1:]


def top_level(body: str) -> str:
    """入れ子の中括弧の中身を除いた、その段だけの文。"""
    out, depth = [], 0
    for ch in body:
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
        elif depth == 0:
            out.append(ch)
    return "".join(out)


def split_top_commas(s: str) -> list:
    parts, depth, cur = [], 0, []
    for ch in s:
        if ch in "([<":
            depth += 1
        elif ch in ")]>":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    parts.append("".join(cur))
    return parts


def core_enums() -> dict:
    enums = {}
    for f in sorted(CORE.rglob("*.swift")):
        s = strip_comments(f.read_text(encoding="utf-8"))
        for m in re.finditer(r"\benum\s+(\w+)", s):
            body = top_level(block_after(s, m.end()))
            cases = set()
            for cm in re.finditer(r"(?:^|\n)\s*(?:indirect\s+)?case\s+([^\n]+)", body):
                for part in split_top_commas(cm.group(1)):
                    nm = re.match(r"\s*`?(\w+)`?", part)
                    if nm:
                        cases.add(nm.group(1))
            if cases:
                # 同じ名前の enum が別の場所にあれば、両方を候補にする
                enums.setdefault(m.group(1), []).append((cases, f.relative_to(ROOT)))
    return enums


def app_switches():
    for base in APPS:
        if not base.exists():
            continue
        for f in sorted(base.rglob("*.swift")):
            raw = f.read_text(encoding="utf-8")
            s = strip_comments(raw)
            for m in re.finditer(r"\bswitch\b[^{\n]*", s):
                body = top_level(block_after(s, m.end()))
                line = raw.count("\n", 0, m.start()) + 1
                if re.search(r"\bdefault\s*:", body):
                    continue
                names = set()
                for cm in re.finditer(r"\bcase\b([^:]*):", body):
                    for nm in re.finditer(r"(?<![\w.])\.(\w+)", cm.group(1)):
                        names.add(nm.group(1))
                if names:
                    yield f.relative_to(ROOT), line, names


def main() -> int:
    enums = core_enums()
    bad = 0
    for path, line, names in app_switches():
        candidates = [(n, c, src) for n, lst in enums.items() for c, src in lst if names <= c]
        if not candidates:
            continue
        missing = [(n, sorted(c - names), src) for n, c, src in candidates]
        if all(m for _, m, _ in missing):
            bad += 1
            for n, m, src in missing:
                print(f"{path}:{line}: switch が {n}({src})を網羅していない。足りない case: {', '.join(m)}")
    if bad:
        print(f"網羅でない switch が {bad} か所(アプリは Linux でコンパイルされないので、ここで直す)")
        return 1
    print("アプリの switch は本体の enum を網羅している")
    return 0


if __name__ == "__main__":
    sys.exit(main())
