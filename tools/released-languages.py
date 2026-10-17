#!/usr/bin/env python3
"""Print the released LanguageID codes from RFKernel/Text.swift."""

import argparse
import pathlib
import re
import sys


TEXT_SWIFT = pathlib.Path(__file__).resolve().parents[1] / "ReForgeCore/Sources/RFKernel/Text.swift"


def released_languages(text: str) -> list[str]:
    cases: dict[str, str] = {}
    for names, value in re.findall(r"\bcase\s+([^=\n]+?)\s*=\s*\"([^\"]+)\"", text):
        name = names.split(",")[-1].strip()
        if re.fullmatch(r"\w+", name):
            cases[name] = value
    match = re.search(r"public\s+static\s+let\s+released\s*:\s*\[LanguageID\]\s*=\s*\[([^\]]*)\]", text)
    if not match:
        raise ValueError("released declaration not found")
    names = re.findall(r"\.([A-Za-z][A-Za-z0-9_]*)", match.group(1))
    if not names:
        raise ValueError("released declaration is empty")
    values: list[str] = []
    for name in names:
        if name == "pseudo":
            raise ValueError("pseudo cannot be released")
        values.append(cases.get(name, name))
    return values


def main() -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--csv", action="store_true")
    args = parser.parse_args()
    try:
        languages = released_languages(TEXT_SWIFT.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        print(f"released-languages: {error}", file=sys.stderr)
        return 1
    print(",".join(languages) if args.csv else "\n".join(languages))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
