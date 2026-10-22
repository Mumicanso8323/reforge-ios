#!/usr/bin/env python3
"""TEST-B4-5 / INV-B4-2: ReForge/ のソースがネットワークの API を参照していないことを確かめる。

操作記録は端末の中だけに残る。通信のコードを足していないことを静的に見る。
StoreKit の購入は OS が行うので、ここでは見ない(Monetization は対象外ではなく、API 名で見る)。
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PATTERNS = [
    r"\bURLSession\b",
    r"\bURLRequest\b",
    r"\bNWConnection\b",
    r"\bNWListener\b",
    r"\bNWPathMonitor\b",
    r"^\s*(@\w+\s+)?import\s+Network\b",
    r"\bCFNetwork\b",
    r"\bCFSocket\b",
    r"\bWKWebView\b",
    r"\bURLSessionWebSocketTask\b",
]


def main() -> int:
    regexes = [re.compile(p, re.MULTILINE) for p in PATTERNS]
    bad: list[str] = []
    for path in sorted((ROOT / "ReForge").rglob("*.swift")):
        text = path.read_text(encoding="utf-8")
        for rx in regexes:
            for m in rx.finditer(text):
                line = text.count("\n", 0, m.start()) + 1
                bad.append(f"{path.relative_to(ROOT)}:{line}: {rx.pattern}")
    if bad:
        print("check-no-network: ネットワークの API を参照している:")
        print("\n".join(bad))
        return 1
    print("check-no-network: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
