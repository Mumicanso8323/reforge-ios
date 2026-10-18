#!/usr/bin/env python3
"""check-languages.py の確かめ(一時ディレクトリの見本で、一致・不一致・Base の扱い)。"""
import importlib.util
import json
import pathlib
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("check_languages", HERE / "check-languages.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

TEXT_SWIFT = '''public enum LanguageID: String {
    case ja, en, zhHans = "zh-Hans", zhHant = "zh-Hant", ko
    case pseudo = "x-pseudo"
    public static let released: [LanguageID] = [%s]
}
'''
PROJECT = "name: ReForge\noptions:\n  developmentLanguage: ja\n%s        INFOPLIST_FILE: Config/ReForge-Info.plist\n"


def info_plist(*locales):
    import plistlib
    return plistlib.dumps({"CFBundleLocalizations": list(locales)}).decode("utf-8")


def snapshot(*untranslated):
    langs = ", ".join(f'("{c}", "x")' for c in ("ja", "en", "zh-Hans", "zh-Hant", "ko"))
    marks = ", ".join(f'"{c}"' for c in untranslated)
    return (f"    private static let languages: [(code: String, locale: String)] = [\n        {langs},\n    ]\n"
            f"    private static let untranslated: Set<String> = [{marks}]\n")


def catalog(*locales):
    strings = {"CFBundleDisplayName": {"localizations": {l: {"stringUnit": {"state": "translated", "value": "x"}} for l in locales}}}
    return json.dumps({"sourceLanguage": "ja", "strings": strings, "version": "1.0"})


class Sample:
    def __init__(self, released=".ja", project_extra="", info_locales=("ja",), development="ja", extra_files=None,
                 plist_locales=("ja",), untranslated=("en", "zh-Hans", "zh-Hant", "ko")):
        self.dir = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.dir.name)
        write(self.root / "ReForgeCore/Sources/RFKernel/Text.swift", TEXT_SWIFT % released)
        write(self.root / "project.yml", (PROJECT % project_extra).replace("developmentLanguage: ja", f"developmentLanguage: {development}"))
        if info_locales is not None:
            write(self.root / MODULE.INFO_PLIST_CATALOG, catalog(*info_locales))
        if plist_locales is not None:
            write(self.root / MODULE.INFO_PLIST, info_plist(*plist_locales))
        if untranslated is not None:
            write(self.root / MODULE.SNAPSHOT_TESTS, snapshot(*untranslated))
        for name, body in (extra_files or {}).items():
            write(self.root / name, body)

    def problems(self):
        return MODULE.check(self.root)

    def close(self):
        self.dir.cleanup()


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class CheckLanguages(unittest.TestCase):
    def sample(self, **kw):
        s = Sample(**kw)
        self.addCleanup(s.close)
        return s

    def test_matching_single_language_passes(self):
        self.assertEqual(self.sample().problems(), [])

    def test_known_regions_are_development_language_base_and_catalog_locales(self):
        s = self.sample()
        self.assertEqual(MODULE.known_regions(s.root), {"ja", "Base"})

    def test_extra_catalog_language_fails(self):
        problems = self.sample(info_locales=("ja", "en")).problems()
        self.assertTrue(any("InfoPlist" in p for p in problems) and any("knownRegions" in p for p in problems), problems)

    def test_other_catalog_adds_a_region(self):
        extra = {"ReForge/Resources/Other.xcstrings": catalog("ko")}
        self.assertTrue(any("knownRegions" in p for p in self.sample(extra_files=extra).problems()))

    def test_lproj_directory_adds_a_region(self):
        extra = {"ReForge/Resources/en.lproj/Foo.strings": ""}
        self.assertTrue(any("knownRegions" in p for p in self.sample(extra_files=extra).problems()))

    def test_released_language_must_leave_snapshot_exemption(self):
        s = self.sample(released=".ja, .en", info_locales=("ja", "en"), plist_locales=("ja", "en"))
        self.assertTrue(any("untranslated" in p for p in s.problems()), "出した言語が免除に残れば落ちる")

    def test_snapshot_exemption_must_cover_untranslated_languages(self):
        self.assertTrue(any("untranslated" in p for p in self.sample(untranslated=("en",)).problems()))

    def test_missing_snapshot_languages_fail(self):
        self.assertTrue(any("untranslated" in p for p in self.sample(untranslated=None).problems()))

    def test_missing_released_language_fails(self):
        self.assertTrue(self.sample(released=".ja, .en").problems())

    def test_adding_a_released_language_requires_project_changes(self):
        s = self.sample(released=".ja, .en", info_locales=("ja", "en"), development="ja", plist_locales=("ja", "en"),
                        untranslated=("zh-Hans", "zh-Hant", "ko"))
        self.assertEqual(MODULE.known_regions(s.root), {"ja", "en", "Base"})
        self.assertEqual(s.problems(), [])

    def test_base_internationalization_off_is_a_mismatch(self):
        problems = self.sample(project_extra="  useBaseInternationalization: false\n").problems()
        self.assertTrue(any("Base" in p for p in problems), problems)

    def test_development_language_must_be_released(self):
        self.assertTrue(self.sample(development="en").problems())

    def test_invalid_keys_in_project_yml_fail(self):
        for extra in ("  knownRegions: [ja]\n", "      INFOPLIST_KEY_CFBundleLocalizations: ja\n"):
            self.assertTrue(self.sample(project_extra=extra).problems(), extra)

    def test_commented_keys_are_ignored(self):
        self.assertEqual(self.sample(project_extra="  # knownRegions is not a key\n").problems(), [])

    def test_missing_info_plist_catalog_fails(self):
        self.assertTrue(self.sample(info_locales=None).problems())

    def test_info_plist_localizations_must_match_released(self):
        problems = self.sample(plist_locales=("ja", "en")).problems()
        self.assertTrue(any("CFBundleLocalizations" in p for p in problems), problems)

    def test_missing_info_plist_fails(self):
        self.assertTrue(any("ReForge-Info.plist" in p for p in self.sample(plist_locales=None).problems()))

    def test_project_must_point_info_plist_file(self):
        s = self.sample()
        write(s.root / "project.yml", "name: ReForge\noptions:\n  developmentLanguage: ja\n")
        self.assertTrue(any("INFOPLIST_FILE" in p for p in s.problems()))


if __name__ == "__main__":
    unittest.main()
