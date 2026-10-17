#!/usr/bin/env python3
"""Keep localized expected strings out of behaviour tests.

An assertion's diagnostic message is deliberately not inspected.  A Japanese
expected value is allowed only when its assertion (or the preceding line) says
why: ``ja-table`` checks a Japanese table and ``ja-ok: ...`` records test data.
"""
import argparse
import json
import re
import sys
from pathlib import Path

JAPANESE = re.compile(r"[\u3040-\u30ff\u3400-\u9fff\uf900-\ufaff]")
ASSERTION = re.compile(r"\bXCTAssert(?:Equal|NotEqual|True|False|Nil|NotNil|GreaterThan|GreaterThanOrEqual|LessThan|LessThanOrEqual|Identical|NotIdentical)\s*\(")
ONE_ARGUMENT = {"XCTAssertTrue", "XCTAssertFalse", "XCTAssertNil", "XCTAssertNotNil"}


def assertion_calls(source):
    """Yield (line, name, arguments) for XCTest calls, including multiline calls."""
    for match in ASSERTION.finditer(source):
        name = match.group(0).split("(", 1)[0].strip()
        start = match.end()
        line = source.count("\n", 0, match.start()) + 1
        depth, quote, escape = 1, None, False
        i = start
        while i < len(source) and depth:
            char = source[i]
            if quote:
                if escape:
                    escape = False
                elif char == "\\":
                    escape = True
                elif char == quote:
                    quote = None
            elif char == '"':
                quote = char
            elif char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
            i += 1
        if depth == 0:
            yield line, name, split_arguments(source[start:i - 1])


def code_only(source):
    """Blank comments while retaining line offsets and quoted strings."""
    out, i, quote, escape, block = [], 0, None, False, False
    while i < len(source):
        char, pair = source[i], source[i:i + 2]
        if block:
            if pair == "*/":
                out.extend("  "); i += 2; block = False
            else:
                out.append("\n" if char == "\n" else " "); i += 1
        elif quote:
            out.append(char)
            if escape: escape = False
            elif char == "\\": escape = True
            elif char == quote: quote = None
            i += 1
        elif char == '"':
            out.append(char); quote = char; i += 1
        elif pair == "//":
            end = source.find("\n", i)
            if end == -1: end = len(source)
            out.extend(" " * (end - i)); i = end
        elif pair == "/*":
            out.extend("  "); i += 2; block = True
        else:
            out.append(char); i += 1
    return "".join(out)


def split_arguments(text):
    parts, start, stack, quote, escape = [], 0, [], None, False
    pairs = {"(": ")", "[": "]", "{": "}"}
    for i, char in enumerate(text):
        if quote:
            if escape:
                escape = False
            elif char == "\\":
                escape = True
            elif char == quote:
                quote = None
        elif char == '"':
            quote = char
        elif char in pairs:
            stack.append(pairs[char])
        elif stack and char == stack[-1]:
            stack.pop()
        elif char == "," and not stack:
            parts.append(text[start:i])
            start = i + 1
    parts.append(text[start:])
    return parts


def candidates(path):
    source = path.read_text(encoding="utf-8")
    lines = source.splitlines()
    out = []
    for line, name, arguments in assertion_calls(code_only(source)):
        checked = arguments[:1] if name in ONE_ARGUMENT else arguments[:2]
        if any(JAPANESE.search(argument) for argument in checked):
            marks = "\n".join(lines[max(0, line - 2):line])
            if "// ja-table" not in marks and "// ja-ok:" not in marks:
                out.append(line)
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--baseline", type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    baseline_path = args.baseline or root / "tools/test-text-literals.baseline.json"
    baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
    current = {}
    for directory in ("ReForgeCore/Tests", "ReForgeTests", "ReForgeUITests"):
        base = root / directory
        if base.exists():
            for path in sorted(base.rglob("*.swift")):
                found = candidates(path)
                if found:
                    current[str(path.relative_to(root))] = len(found)
    failed = False
    for path in sorted(set(current) | set(baseline)):
        got, limit = current.get(path, 0), baseline.get(path, 0)
        if got > limit:
            print(f"{path}: {got}")
            failed = True
        elif got < limit:
            print(f"{path}: {got} (lower baseline from {limit})")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
