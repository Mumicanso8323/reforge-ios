#!/usr/bin/env python3
"""公開リポジトリに物語の語(非公開の層の禁止語)が入っていないかを確かめる。

照らし合わせる語は、非公開の層の perception/forbidden.json の forbidden[].words(全部の段の語)。
非公開の層は content/private(または環境変数 REFORGE_PRIVATE_CONTENT)。無ければ何もせずに通す
(fork の PR など。CI の公開のログに語を出さないため、一致した語そのものは決して表示しない)。

見るもの:
- 既定: git が追う・追っていない(無視されていない)公開リポジトリのファイル全部(content/private は無視されている)。
- --commits <範囲>: その範囲のコミットのメッセージ(例: origin/main..HEAD。push する前に)。

出すのは「ファイル:行」(コミットならハッシュ)と件数だけ。語・前後の文は出さない。
使い方: python3 tools/check-public-spoilers.py [--commits origin/main..HEAD]   (一致があれば終了コード 1)
"""
import json
import os
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def private_layer() -> pathlib.Path | None:
    env = os.environ.get("REFORGE_PRIVATE_CONTENT")
    p = pathlib.Path(env) if env else ROOT / "content" / "private"
    return p if p.is_dir() else None


def load_words(layer: pathlib.Path) -> list:
    words = set()
    for f in sorted(layer.rglob("*.json")):
        rel = f.relative_to(layer).as_posix()
        if rel.startswith(("materials/", "tools/")) or "/." in "/" + rel:
            continue
        try:
            data = json.loads(f.read_text(encoding="utf-8"))
        except (ValueError, UnicodeDecodeError):
            continue
        if isinstance(data, dict):
            for rule in data.get("forbidden") or []:
                for w in rule.get("words") or []:
                    if isinstance(w, str) and w.strip():
                        words.add(w.strip())
    return sorted(words, key=len, reverse=True)


def matcher(words: list):
    """ラテン文字を含む語は、前後がラテン文字・数字・_ でないときだけ当たる(環境変数の名前の一部などは当たらない)。
    大文字と小文字は区別する(書かれたとおり。題名の Re:Forge と大文字の固有名を分ける)。日本語の語は部分一致。"""
    import re
    pats = []
    for w in words:
        if re.search(r"[A-Za-z0-9]", w):
            pats.append(re.compile(r"(?<![A-Za-z0-9_])" + re.escape(w) + r"(?![A-Za-z0-9_])"))
        else:
            pats.append(re.compile(re.escape(w)))

    def hit(line: str) -> bool:
        return any(p.search(line) for p in pats)
    return hit


def public_files() -> list:
    out = subprocess.run(["git", "-C", str(ROOT), "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
                         check=True, capture_output=True).stdout
    paths = [p for p in out.decode("utf-8").split("\0") if p]
    return [p for p in paths if not p.startswith("content/private/") and (ROOT / p).is_file()]


def main() -> int:
    layer = private_layer()
    if layer is None:
        print("非公開の層が無いので、物語の語の検査は飛ばす")
        return 0
    words = load_words(layer)
    if not words:
        print("非公開の層に禁止語が無い(forbidden.json を確かめる)")
        return 1
    hit = matcher(words)
    found = []

    args = sys.argv[1:]
    if len(args) == 2 and args[0] == "--commits":
        log = subprocess.run(["git", "-C", str(ROOT), "log", "--format=%H%x00%B%x01", args[1]],
                             check=True, capture_output=True).stdout.decode("utf-8", "replace")
        for entry in log.split("\x01"):
            if "\x00" not in entry:
                continue
            sha, body = entry.split("\x00", 1)
            if hit(body):
                found.append(f"コミット {sha.strip()[:10]} のメッセージ")
    elif args:
        print(__doc__)
        return 2
    else:
        for rel in public_files():
            try:
                text = (ROOT / rel).read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError):
                continue  # 絵・フォントなど
            for n, line in enumerate(text.splitlines(), 1):
                if hit(line):
                    found.append(f"{rel}:{n}")

    for f in found:
        print(f)
    if found:
        print(f"物語の語が公開リポジトリに {len(found)} か所ある(語はログに出さない。手元で該当の行を見て直す)")
        return 1
    print(f"物語の語は見つからない(語 {len(words)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
