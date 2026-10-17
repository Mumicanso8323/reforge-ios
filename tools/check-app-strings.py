#!/usr/bin/env python3
"""アプリ(ReForge/Sources)の固定文言が、文言の表(content/public/text/ja/app*.json)から引かれていることを確かめる(L-11・TEST-L10)。

規則(外れたら終了コード 1。出すのは「ファイル:行」と規則の番号だけ):
 1. 直書きが無い: コメントを除く文字列リテラルに、かな・漢字・ハングル・全角の約物(U+3000〜303F・U+FF00〜FFEF)を含む物は、
    許可の一覧 tools/app-strings-allow.json(ファイル → 許すリテラル)の物と、`#if DEBUG … #endif` の中と ReForge/Sources/Debug/ だけ。
    それ以外はファイルごとの基準 tools/app-strings-baseline.json(ファイル → まだ移していない数。ratchet)を超えたら失敗。
    基準より少なくなったら基準を下げること(--write-baseline が下げる。上げる向きには書かない)。
 2. 使っている ui("…")・UIText.shared.string("…") の ID が表(content/public/text/ja/*.json)にある。
    渡す引数の名前(["n": …])が、日本語の文の引数の名前の集まりと同じ(行内で読める範囲)。
 3. 表の app*.json の ui.* の ID が、アプリのコードのどこかから使われている。
    (ui.daywrap.*・ui.roster.*・ui.grant.*・ui.finding.* など本体が使う ID は app*.json に置かないので対象外)
 4. app*.json の ID と、コードで使う ID が ui.<区分>.<名前> の形(区分は button・band・tab・card・bubble・prologue・label・body・a11y)。
 5. ui( ・ UIText.shared.string( の引数が文字列リテラルだけ(動的な組み立てをしない)。
 6. 約物・区切りの連結: Text(…) + Text(…) の類と、Text(verbatim: "…\\(…)…") で、かな・漢字・約物を含む固定の字を補間でつなぐ物。
    (本体が組んだ文・名前を verbatim: で出すのは可。かな・漢字・約物を含まない補間だけの物も可)

使い方:
  python3 tools/check-app-strings.py                        規則を確かめる
  python3 tools/check-app-strings.py --write-baseline       基準を、いまの数まで下げる(上げない)
  python3 tools/check-app-strings.py --parity-with-catalog  旧 Localizable.xcstrings の全キーが表の値のどれかと一致するか(第 3 回の確認)
"""
import argparse
import json
import re
import sys
from pathlib import Path

JAPANESE = re.compile(r"[぀-ヿ㐀-鿿豈-﫿가-힯　-〿＀-￯]")
KINDS = ("button", "band", "tab", "card", "bubble", "prologue", "label", "body", "a11y")
ID_SHAPE = re.compile(r"^ui\.(?:%s)\.[a-z][a-z0-9_]*$" % "|".join(KINDS))
CALL = re.compile(r"(?<![\w.])(?<!func )(ui|UIText\.shared\.string)\(")
UI_TEXT_FILE = "ReForge/Sources/Theme/UIText.swift"
ARG_NAME = re.compile(r"\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*[,}]")
DICT_KEY = re.compile(r'[\[,]\s*"([A-Za-z_][A-Za-z0-9_]*)"\s*:')


def scan_strings(source):
    """コメントを空白に替え、文字列リテラルを [(開始, 終了, 本文)] で返す。本文は外側の引用符の間(補間の中の入れ子も本文に含む)。
    返す masked は、コメントを空白にした元の文字列(位置は元と同じ)。"""
    out, literals, i, n = list(source), [], 0, len(source)

    def string(start):
        """start は開きの引用符の位置。閉じの位置を返す(補間の中の入れ子の文字列も飛ばす)。"""
        j = start + 1
        while j < n:
            c = source[j]
            if c == "\\":
                if source[j + 1:j + 2] == "(":
                    depth, j = 1, j + 2
                    while j < n and depth:
                        if source[j] == '"':
                            j = string(j) + 1
                            continue
                        depth += {"(": 1, ")": -1}.get(source[j], 0)
                        j += 1
                    continue
                j += 2
                continue
            if c == '"':
                return j
            j += 1
        return n - 1

    while i < n:
        pair = source[i:i + 2]
        if source[i] == '"':
            end = string(i)
            literals.append((i, end, source[i + 1:end]))
            # 補間の中の入れ子の文字列も別のリテラルとして拾う
            j = i + 1
            while j < end:
                if source[j] == "\\" and source[j + 1:j + 2] == "(":
                    depth, k = 1, j + 2
                    while k < end and depth:
                        if source[k] == '"':
                            k = string(k) + 1
                            continue
                        depth += {"(": 1, ")": -1}.get(source[k], 0)
                        k += 1
                    for start, stop, body in scan_strings(source[j + 2:k - 1])[1]:
                        literals.append((j + 2 + start, j + 2 + stop, body))
                    j = k
                else:
                    j += 2 if source[j] == "\\" else 1
            i = end + 1
        elif pair == "//":
            end = source.find("\n", i)
            end = n if end < 0 else end
            for k in range(i, end):
                out[k] = " "
            i = end
        elif pair == "/*":
            end = source.find("*/", i + 2)
            end = n if end < 0 else end + 2
            for k in range(i, end):
                if source[k] != "\n":
                    out[k] = " "
            i = end
        else:
            i += 1
    return "".join(out), literals


def static_text(body):
    """リテラルの本文から、補間 \\( … \\) を除いた固定の字。"""
    out, i = [], 0
    while i < len(body):
        if body.startswith("\\(", i):
            depth, i = 1, i + 2
            while i < len(body) and depth:
                depth += {"(": 1, ")": -1}.get(body[i], 0)
                i += 1
            continue
        out.append(body[i])
        i += 1
    return "".join(out)


def has_japanese(body):
    return bool(JAPANESE.search(static_text(body)))


def debug_lines(text):
    """行番号(1 始まり)→ #if DEBUG(|| REFORGE_DEV)の中か。#else 側は含めない。"""
    flags, stack = {}, []
    for number, line in enumerate(text.splitlines(), 1):
        word = line.strip()
        if word.startswith("#if"):
            cond = re.sub(r"\s+", "", word[3:])
            stack.append(["debug" if cond in ("DEBUG", "DEBUG||REFORGE_DEV", "REFORGE_DEV||DEBUG") else "other", False])
        elif word.startswith("#elseif") or word.startswith("#else"):
            if stack:
                stack[-1][1] = True
        elif word.startswith("#endif"):
            if stack:
                stack.pop()
        flags[number] = any(kind == "debug" and not flipped for kind, flipped in stack)
    return flags


def line_of(text, index):
    return text.count("\n", 0, index) + 1


def match_paren(masked, open_index):
    """masked[open_index] の "(" に対応する ")" の位置(文字列の中の括弧は数えない)。"""
    depth, i, n = 0, open_index, len(masked)
    while i < n:
        c = masked[i]
        if c == '"':
            i = skip_string(masked, i) + 1
            continue
        depth += {"(": 1, ")": -1}.get(c, 0)
        if depth == 0:
            return i
        i += 1
    return n - 1


def skip_string(text, start):
    j, n = start + 1, len(text)
    while j < n:
        c = text[j]
        if c == "\\":
            if text[j + 1:j + 2] == "(":
                depth, j = 1, j + 2
                while j < n and depth:
                    if text[j] == '"':
                        j = skip_string(text, j) + 1
                        continue
                    depth += {"(": 1, ")": -1}.get(text[j], 0)
                    j += 1
                continue
            j += 2
            continue
        if c == '"':
            return j
        j += 1
    return n - 1


def blank_strings(masked):
    """文字列リテラルの中身を空白にした版(記号の探索用)。"""
    _, literals = scan_strings(masked)
    out = list(masked)
    for start, end, _ in literals:
        for k in range(start + 1, end):
            if out[k] != "\n":
                out[k] = " "
    return "".join(out)


def load_tables(root):
    """ja の表全部 → {ID: 文}、app*.json だけ → {ID: 文}。"""
    everything, app = {}, {}
    directory = root / "content" / "public" / "text" / "ja"
    for path in sorted(directory.glob("*.json")):
        if path.name.startswith("_"):
            continue
        texts = json.loads(path.read_text(encoding="utf-8")).get("texts", {})
        everything.update(texts)
        if path.name.startswith("app"):
            app.update(texts)
    return everything, app


def argument_names(pattern):
    return set(ARG_NAME.findall(pattern))


def sources(root):
    base = root / "ReForge" / "Sources"
    return sorted(base.rglob("*.swift")) if base.exists() else []


def literal_hits(root):
    """規則 1 の対象(許可・DEBUG・Debug/ を除いた直書き)を {相対パス: [行]} で返す。"""
    allow_path = root / "tools" / "app-strings-allow.json"
    allow = json.loads(allow_path.read_text(encoding="utf-8")) if allow_path.exists() else {}
    hits = {}
    for path in sources(root):
        relative = path.relative_to(root).as_posix()
        if "/Sources/Debug/" in relative:
            continue
        text = path.read_text(encoding="utf-8")
        _, literals = scan_strings(text)
        flags = debug_lines(text)
        permitted = set(allow.get(relative, []))
        for start, _, body in literals:
            if not has_japanese(body):
                continue
            number = line_of(text, start)
            if flags.get(number) or body in permitted:
                continue
            hits.setdefault(relative, []).append(number)
    return hits


def check(root):
    """違反の一覧 [(規則, 相対パス, 行)] を返す。"""
    problems = []
    everything, app = load_tables(root)
    baseline_path = root / "tools" / "app-strings-baseline.json"
    baseline = json.loads(baseline_path.read_text(encoding="utf-8")) if baseline_path.exists() else {}

    # 1
    hits = literal_hits(root)
    for relative in sorted(set(hits) | set(baseline)):
        lines = hits.get(relative, [])
        if len(lines) > baseline.get(relative, 0):
            problems.extend((1, relative, line) for line in lines)
        elif len(lines) < baseline.get(relative, 0):
            problems.append((1, relative, 0))  # 基準が高すぎる(--write-baseline で下げる)

    used = set()
    for path in sources(root):
        relative = path.relative_to(root).as_posix()
        text = path.read_text(encoding="utf-8")
        masked, literals = scan_strings(text)
        flags = debug_lines(text)
        in_debug_dir = "/Sources/Debug/" in relative
        for call in CALL.finditer(masked):
            open_index = call.end() - 1
            number = line_of(text, call.start())
            close = match_paren(masked, open_index)
            inside = masked[open_index + 1:close]
            stripped = inside.lstrip()
            offset = open_index + 1 + (len(inside) - len(stripped))
            if not stripped.startswith('"'):
                if relative != UI_TEXT_FILE:  # 口の実装そのもの(引数をそのまま表へ渡す)だけは動的でよい
                    problems.append((5, relative, number))
                continue
            end = skip_string(masked, offset)
            literal = masked[offset + 1:end]
            rest = masked[end + 1:close].lstrip()
            if "\\(" in literal or (rest and not rest.startswith(",")):
                problems.append((5, relative, number))
                continue
            used.add(literal)
            # 本体が使う ID(ui.roster.*・ui.grant.* など。app*.json に無い物)は形の対象にしない
            if not ID_SHAPE.match(literal) and (literal in app or literal not in everything):
                problems.append((4, relative, number))
            if literal not in everything:
                problems.append((2, relative, number))
                continue
            given = set(DICT_KEY.findall(rest))
            if given != argument_names(everything[literal]):
                problems.append((2, relative, number))
        if in_debug_dir:
            continue
        # 6(まだ移していない物が残るファイル=基準が 0 でないファイルは、移し終えるまで対象にしない)
        if baseline.get(relative, 0) > 0:
            continue
        blanked = blank_strings(masked)
        for found in re.finditer(r"\b(?:Text|ui)\s*\(", blanked):
            number = line_of(text, found.start())
            if flags.get(number):
                continue
            close = match_paren(blanked, found.end() - 1)
            tail = blanked[close + 1:close + 12].lstrip()
            head = blanked[max(0, found.start() - 12):found.start()].rstrip()
            if (tail.startswith("+") and not tail.startswith("++")) or (head.endswith("+") and not head.endswith("++")):
                problems.append((6, relative, number))
        for start, _, body in literals:
            before = masked[max(0, start - 20):start].rstrip()
            number = line_of(text, start)
            if before.endswith("verbatim:") and "\\(" in body and has_japanese(body) and not flags.get(number):
                problems.append((6, relative, number))

    # 3・4(表の側)
    for identifier in sorted(app):
        if not ID_SHAPE.match(identifier):
            problems.append((4, "content/public/text/ja", 0))
        elif identifier not in used:
            problems.append((3, "content/public/text/ja", 0))
    return sorted(set(problems))


def write_baseline(root):
    path = root / "tools" / "app-strings-baseline.json"
    old = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    hits = literal_hits(root)
    new = {}
    for relative in sorted(set(old) | set(hits)):
        count = len(hits.get(relative, []))
        count = min(count, old[relative]) if relative in old else count
        if count:
            new[relative] = count
    path.write_text(json.dumps(new, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"基準を書いた: {sum(new.values())} 件({len(new)} ファイル)")


# 旧カタログのキーのうち、表の文に移さなかった物(漢数字の表も断片:コードの表をやめて「割くらい」の文が持つ。断片の連結をやめて 1 つの差し込みの文にしたため)。
RETIRED_FRAGMENTS = {"残り", "回", "手ざわり: ", "割くらい", "日目", "必要: ", *"一二三四五六七八九十"}


def parity(root, catalog=None):
    """旧カタログの全キーが、%lld・%@ を {名前} に読み替えて、表の値のどれかと一致するか。"""
    catalog_path = catalog or root / "ReForge" / "Resources" / "Localizable.xcstrings"
    if not catalog_path.exists():
        print("旧カタログ(Localizable.xcstrings)は無い")
        return 0
    keys = list(json.loads(catalog_path.read_text(encoding="utf-8"))["strings"])
    everything, _ = load_tables(root)

    def shape(value):
        return re.sub(r"\{[A-Za-z_][A-Za-z0-9_]*\}", "\x00", value)

    values = {shape(v) for v in everything.values()}
    debug_bodies = []
    allow_path = root / "tools" / "app-strings-allow.json"
    if allow_path.exists():  # 許可の一覧(名前の表・開発者向けの組み立て)も、表に移さない物
        for literals in json.loads(allow_path.read_text(encoding="utf-8")).values():
            debug_bodies.extend(static_text(body) for body in literals)
    for path in sources(root):
        text = path.read_text(encoding="utf-8")
        flags = debug_lines(text)
        in_debug_dir = "/Sources/Debug/" in path.as_posix()
        for start, _, body in scan_strings(text)[1]:
            if in_debug_dir or flags.get(line_of(text, start)):
                debug_bodies.append(static_text(body))
    matched, retired, developer, missing = 0, [], [], []
    for key in keys:
        if re.sub(r"%lld|%@", "\x00", key.replace("%%", "%")) in values:
            matched += 1
        elif key in RETIRED_FRAGMENTS:
            retired.append(key)
        elif any(all(piece in body for piece in re.split(r"%lld|%@", key.replace("%%", "%")) if piece) for body in debug_bodies):
            developer.append(key)
        else:
            missing.append(key)
    print(f"旧カタログのキー {len(keys)} 件: 表の値と一致 {matched} 件・断片の連結を 1 つの文にして廃止 {len(retired)} 件"
          f"・開発者向け(#if DEBUG の中。移さない) {len(developer)} 件・一致しない {len(missing)} 件")
    for key in retired:
        print(f"  廃止した断片: {key!r}")
    for key in developer:
        print(f"  開発者向け: {key!r}")
    for key in missing:
        print(f"  一致しない: {key!r}")
    return 1 if missing else 0


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--write-baseline", action="store_true")
    parser.add_argument("--parity-with-catalog", action="store_true")
    parser.add_argument("--catalog", type=Path, help="--parity-with-catalog で読む旧カタログ(既定は ReForge/Resources/Localizable.xcstrings)")
    args = parser.parse_args(argv)
    root = args.root.resolve()
    if args.write_baseline:
        write_baseline(root)
        return 0
    if args.parity_with_catalog:
        return parity(root, args.catalog)
    problems = check(root)
    if problems:
        print("アプリの固定文言が表を通っていない(規則 → ファイル:行):")
        for rule, relative, line in problems:
            print(f"  [{rule}] {relative}:{line}" if line else f"  [{rule}] {relative}")
        return 1
    print("アプリの固定文言は表を通っている")
    return 0


if __name__ == "__main__":
    sys.exit(main())
