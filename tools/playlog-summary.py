#!/usr/bin/env python3
"""Summarize local JSON Lines play records using only the standard library."""
import argparse
import collections
import json
import pathlib
import sys


def records(paths):
    for path in paths:
        with path.open(encoding="utf-8") as source:
            for number, line in enumerate(source, 1):
                if not line.strip():
                    continue
                try:
                    value = json.loads(line)
                except json.JSONDecodeError as error:
                    raise SystemExit(f"{path}:{number}: {error}")
                if isinstance(value, dict):
                    yield value


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="+", type=pathlib.Path)
    args = parser.parse_args()
    paths = [item for path in args.paths for item in (sorted(path.glob("*.jsonl")) if path.is_dir() else [path])]
    items = list(records(paths))
    counts = collections.Counter(item.get("kind", "unknown") for item in items)
    zones = collections.Counter(item.get("fields", {}).get("zone") for item in items if item.get("fields", {}).get("zone"))
    reselects = sum(item.get("fields", {}).get("reselect") == "true" for item in items if item.get("kind") == "select")
    print("kind\tcount")
    for kind, count in sorted(counts.items()):
        print(f"{kind}\t{count}")
    print(f"reselect\t{reselects}")
    for zone in ("top", "middle", "bottom"):
        print(f"zone.{zone}\t{zones[zone]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
