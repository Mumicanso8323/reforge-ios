#!/usr/bin/env python3
import importlib.util
import pathlib
import tempfile
import unittest


HERE = pathlib.Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("released_languages", HERE / "released-languages.py")
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def sample(released: str) -> str:
    return f'''public enum LanguageID: String {{
    case ja, en, zhHans = "zh-Hans", zhHant = "zh-Hant", ko
    case pseudo = "x-pseudo"
    public static let released: [LanguageID] = [{released}]
}}'''


class ReleasedLanguagesTests(unittest.TestCase):
    def test_one_language(self) -> None:
        self.assertEqual(MODULE.released_languages(sample(".ja")), ["ja"])

    def test_multiple_languages_and_raw_value(self) -> None:
        self.assertEqual(MODULE.released_languages(sample(".ja, .zhHans, .ko")), ["ja", "zh-Hans", "ko"])

    def test_unreadable_declaration_fails(self) -> None:
        with self.assertRaises(ValueError):
            MODULE.released_languages("public enum LanguageID {}")

    def test_repository_is_japanese_only_by_owner_decision(self) -> None:
        source = (HERE.parent / "ReForgeCore/Sources/RFKernel/Text.swift").read_text(encoding="utf-8")
        self.assertEqual(MODULE.released_languages(source), ["ja"],
                         "出す言語を変えるのは本人の決め")


if __name__ == "__main__":
    unittest.main()
