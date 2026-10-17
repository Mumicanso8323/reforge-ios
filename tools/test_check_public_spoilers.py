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
    def run_checker(self, source: str, rules: dict, forbidden: dict | None = None) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            tools = root / "tools"
            private_tools = root / "private" / "tools"
            tools.mkdir(parents=True)
            private_tools.mkdir(parents=True)
            shutil.copy2(CHECKER, tools / CHECKER.name)
            (root / "sample.txt").write_text(source)
            (private_tools / "public-words.json").write_text(json.dumps(rules))
            if forbidden is not None:
                (root / "private" / "forbidden.json").write_text(json.dumps(forbidden))
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

    def test_pattern_across_lines_hits(self) -> None:
        rules = {"publicOnlyWords": [], "publicOnlyPatterns": ["zorb\\s+left"],
                 "publicOnlyIdentifiers": [], "identifierExceptions": []}
        result = self.run_checker("ok\nzorb\nleft\n", rules)
        self.assertEqual(result.returncode, 1)
        self.assertIn("sample.txt:2", result.stdout)
        self.assertNotIn("zorb", result.stdout)

    def test_decomposed_synthetic_word_hits(self) -> None:
        rules = {"publicOnlyWords": ["zo\u0308rb"], "publicOnlyPatterns": [],
                 "publicOnlyIdentifiers": [], "identifierExceptions": []}
        result = self.run_checker("z\u006f\u0308rb\n", rules)
        self.assertEqual(result.returncode, 1)

    def test_language_object_matches_korean_and_chinese_substrings(self) -> None:
        rules = {"publicOnlyWords": [],
                 "publicOnlyPatterns": [], "publicOnlyIdentifiers": [], "identifierExceptions": []}
        forbidden = {"forbidden": [{"words": {"ko": ["zorbko"], "zh-Hans": ["zorbzh"]}}]}
        result = self.run_checker("zorbko\uc744\n\u7532zorbzh\u4e59\n", rules, forbidden)
        self.assertEqual(result.returncode, 1)
        self.assertIn("sample.txt:1", result.stdout)
        self.assertIn("sample.txt:2", result.stdout)

    def test_language_object_only_uses_capitalized_english_words_at_boundaries(self) -> None:
        rules = {"publicOnlyWords": [],
                 "publicOnlyPatterns": [], "publicOnlyIdentifiers": [], "identifierExceptions": []}
        forbidden = {"forbidden": [{"words": {"en": ["zorblow", "Zorbleft"]}}]}
        result = self.run_checker("Zorbleft\nZorblefty\nxZorbleft\nzorblow\n", rules, forbidden)
        self.assertEqual(result.returncode, 1)
        self.assertIn("sample.txt:1", result.stdout)
        self.assertNotIn("sample.txt:2", result.stdout)
        self.assertNotIn("sample.txt:3", result.stdout)
        self.assertNotIn("sample.txt:4", result.stdout)
        self.assertNotIn("Zorbleft", result.stdout)
        self.assertNotIn("zorblow", result.stdout)

    def test_legacy_arrays_remain_active(self) -> None:
        rules = {"publicOnlyWords": ["zorbextra"], "publicOnlyPatterns": [],
                 "publicOnlyIdentifiers": [], "identifierExceptions": []}
        forbidden = {"forbidden": [{"words": ["zorbarray"]}]}
        result = self.run_checker("zorbarray\nzorbextra\n", rules, forbidden)
        self.assertEqual(result.returncode, 1)
        self.assertIn("sample.txt:1", result.stdout)
        self.assertIn("sample.txt:2", result.stdout)

    def test_pronoun_rules_do_not_participate(self) -> None:
        rules = {"publicOnlyWords": ["zorbpublic"], "publicOnlyPatterns": [],
                 "publicOnlyIdentifiers": [], "identifierExceptions": []}
        forbidden = {"pronounRules": [{"error": ["zorbpronoun"]}]}
        result = self.run_checker("zorbpronoun\n", rules, forbidden)
        self.assertEqual(result.returncode, 0)
        self.assertNotIn("sample.txt:", result.stdout)
        self.assertNotIn("zorbpronoun", result.stdout)

    def test_unknown_language_key_fails_without_exposing_words(self) -> None:
        rules = {"publicOnlyWords": [], "publicOnlyPatterns": [],
                 "publicOnlyIdentifiers": [], "identifierExceptions": []}
        forbidden = {"forbidden": [{"words": {"x-zorb": ["zorbsecret"]}}]}
        result = self.run_checker("safe\n", rules, forbidden)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("(\u8a00\u8a9e\u306e\u9375)", result.stderr)
        self.assertNotIn("zorbsecret", result.stdout + result.stderr)

    def test_object_hit_output_does_not_expose_word(self) -> None:
        rules = {"publicOnlyWords": {"en": ["Zorbname"]}, "publicOnlyPatterns": [],
                 "publicOnlyIdentifiers": [], "identifierExceptions": []}
        result = self.run_checker("Zorbname\n", rules)
        self.assertEqual(result.returncode, 1)
        self.assertIn("sample.txt:1", result.stdout)
        self.assertNotIn("Zorbname", result.stdout)

    def test_success_reports_language_breakdown(self) -> None:
        rules = {"publicOnlyWords": {"ja": ["zorbja"], "en": ["Zorben"]},
                 "publicOnlyPatterns": [], "publicOnlyIdentifiers": [], "identifierExceptions": []}
        result = self.run_checker("safe\n", rules)
        self.assertEqual(result.returncode, 0)
        self.assertIn("語 2(ja 1・en 1)", result.stdout)


if __name__ == "__main__":
    unittest.main()
