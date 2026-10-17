#!/usr/bin/env python3
"""Reject localized display literals in core presentation and perception code."""
import argparse
import json
import re
import sys
from pathlib import Path

LOCALIZED = re.compile(r"[\u3040-\u30ff\u3400-\u9fff\uf900-\ufaff\uac00-\ud7af]")
STRING = re.compile(r'"(?:\\.|[^"\\])*"')


def uncomment(source):
    out, i, quote, escape, block = [], 0, False, False, False
    while i < len(source):
        char, pair = source[i], source[i:i + 2]
        if block:
            if pair == "*/": out.extend("  "); i += 2; block = False
            else: out.append("\n" if char == "\n" else " "); i += 1
        elif quote:
            out.append(char)
            if escape: escape = False
            elif char == "\\": escape = True
            elif char == '"': quote = False
            i += 1
        elif char == '"': out.append(char); quote = True; i += 1
        elif pair == "//":
            end = source.find("\n", i)
            if end == -1: end = len(source)
            out.extend(" " * (end - i)); i = end
        elif pair == "/*": out.extend("  "); i += 2; block = True
        else: out.append(char); i += 1
    return "".join(out)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--allow", type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    allow_path = args.allow or root / "tools/core-strings-allow.json"
    allowed = json.loads(allow_path.read_text(encoding="utf-8"))
    failed = False
    for area in ("ReForgeCore/Sources/RFPresent", "ReForgeCore/Sources/RFPerception"):
        for path in sorted((root / area).glob("*.swift")):
            relative = str(path.relative_to(root))
            permitted = set(allowed.get(relative, []))
            for number, raw in enumerate(uncomment(path.read_text(encoding="utf-8")).splitlines(), 1):
                for literal in STRING.findall(raw):
                    value = literal[1:-1]
                    if LOCALIZED.search(value) and value not in permitted:
                        print(f"{relative}:{number}")
                        failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
