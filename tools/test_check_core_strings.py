#!/usr/bin/env python3
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("check-core-strings.py")


class CoreStringCheckTests(unittest.TestCase):
    def run_check(self, source, allowed=()):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            path = root / "ReForgeCore/Sources/RFPresent/Example.swift"
            path.parent.mkdir(parents=True)
            path.write_text(source, encoding="utf-8")
            allow = root / "allow.json"
            allow.write_text(json.dumps({str(path.relative_to(root)): list(allowed)}), encoding="utf-8")
            return subprocess.run([sys.executable, str(SCRIPT), "--root", str(root), "--allow", str(allow)], text=True, capture_output=True)

    def test_allow_comment_and_symbols(self):
        result = self.run_check('// "日本語"\n/* "日本語" */\nlet marker = "？"\nlet allowed = "日本語"', ["日本語"])
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_unlisted_and_hangul_fail(self):
        result = self.run_check('let one = "日本語"\nlet two = "한국어"')
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout.splitlines(), [
            "ReForgeCore/Sources/RFPresent/Example.swift:1",
            "ReForgeCore/Sources/RFPresent/Example.swift:2",
        ])


if __name__ == "__main__":
    unittest.main()
