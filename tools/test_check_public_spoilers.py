#!/usr/bin/env python3
import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest


HERE = pathlib.Path(__file__).resolve().parent
CHECKER = HERE / "check-public-spoilers.py"


class PublicSpoilerCheckerTests(unittest.TestCase):
    def run_checker(self, source: str, rules: dict) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            tools = root / "tools"
            private_tools = root / "private" / "tools"
            tools.mkdir(parents=True)
            private_tools.mkdir(parents=True)
            shutil.copy2(CHECKER, tools / CHECKER.name)
            (root / "sample.txt").write_text(source)
            (private_tools / "public-words.json").write_text(json.dumps(rules))
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            subprocess.run(["git", "add", "sample.txt", "tools"], cwd=root, check=True)
            env = os.environ | {"REFORGE_PRIVATE_CONTENT": str(root / "private")}
            return subprocess.run(["python3", str(tools / CHECKER.name)], cwd=root, env=env,
                                  text=True, capture_output=True)

    def test_pattern_and_identifier_hits_do_not_reveal_rule_text(self) -> None:
        rules = {
            "publicOnlyWords": [],
            "publicOnlyPatterns": ["zorb[0-9]+"],
            "publicOnlyIdentifiers": ["zorbleft"],
            "identifierExceptions": ["SafeZorbleftType"],
        }
        result = self.run_checker("zorb42\nvalue = setZorbleft\nSafeZorbleftType\n", rules)
        self.assertEqual(result.returncode, 1)
        self.assertIn("sample.txt:1", result.stdout)
        self.assertIn("sample.txt:2", result.stdout)
        self.assertNotIn("zorb42", result.stdout)
        self.assertNotIn("setZorbleft", result.stdout)

    def test_exception_allows_the_complete_identifier(self) -> None:
        rules = {
            "publicOnlyWords": [],
            "publicOnlyPatterns": [],
            "publicOnlyIdentifiers": ["zorbleft"],
            "identifierExceptions": ["SafeZorbleftType"],
        }
        result = self.run_checker("SafeZorbleftType\n", rules)
        self.assertEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
