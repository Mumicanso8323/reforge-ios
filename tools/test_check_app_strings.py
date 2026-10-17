#!/usr/bin/env python3
"""check-app-strings.py と check-no-reason-text.py の確かめ(一時ディレクトリの見本で、各規則の内と外を見る)。"""
import importlib.util
import json
import pathlib
import tempfile
import unittest

TOOLS = pathlib.Path(__file__).resolve().parent


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, TOOLS / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


checker = load("check_app_strings", "check-app-strings.py")
reason = load("check_no_reason_text", "check-no-reason-text.py")

TABLE = {
    "ui.button.sleep": "寝る",
    "ui.band.remaining": "残り {n} 回",
    "ui.body.unused": "使われない",
}


class Sample:
    def __init__(self, files, table=None, allow=None, baseline=None):
        self.dir = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.dir.name)
        text = self.root / "content" / "public" / "text" / "ja"
        text.mkdir(parents=True)
        (text / "app.json").write_text(json.dumps({"language": "ja", "texts": TABLE if table is None else table}, ensure_ascii=False), encoding="utf-8")
        (text / "core_ui.json").write_text(json.dumps({"language": "ja", "texts": {"ui.daywrap.sep": "。"}}), encoding="utf-8")
        for name, body in files.items():
            path = self.root / "ReForge" / "Sources" / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(body, encoding="utf-8")
        tools = self.root / "tools"
        tools.mkdir()
        (tools / "app-strings-allow.json").write_text(json.dumps(allow or {}, ensure_ascii=False), encoding="utf-8")
        (tools / "app-strings-baseline.json").write_text(json.dumps(baseline or {}), encoding="utf-8")

    def rules(self):
        return sorted({rule for rule, _, _ in checker.check(self.root)})

    def close(self):
        self.dir.cleanup()


USES_ALL = 'ui("ui.button.sleep"); ui("ui.band.remaining", ["n": .int(1)]); ui("ui.body.unused")\n'


class CheckAppStrings(unittest.TestCase):
    def run_sample(self, files, **kw):
        sample = Sample({"Used.swift": USES_ALL, **files}, **kw)
        self.addCleanup(sample.close)
        return sample

    def test_clean(self):
        self.assertEqual(self.run_sample({}).rules(), [])

    # 規則 1
    def test_hardcoded_literal_fails(self):
        self.assertEqual(self.run_sample({"A.swift": 'Text("寝る")\n'}).rules(), [1])

    def test_fullwidth_punctuation_fails(self):
        self.assertEqual(self.run_sample({"A.swift": 'let s = "a、b"\n'}).rules(), [1])
        self.assertEqual(self.run_sample({"A.swift": 'let s = "a？"\n'}).rules(), [1])

    def test_comments_and_debug_and_debug_dir_are_free(self):
        files = {
            "A.swift": '// Text("寝る")\nlet x = 1 // "寝る"\n/* "寝る" */\n#if DEBUG\nlet d = "開発"\n#endif\n',
            "Debug/D.swift": 'let d = "開発"\n',
        }
        self.assertEqual(self.run_sample(files).rules(), [])

    def test_else_side_of_debug_is_not_free(self):
        self.assertEqual(self.run_sample({"A.swift": '#if DEBUG\nlet a = 1\n#else\nlet d = "本番"\n#endif\n'}).rules(), [1])

    def test_allow_list_and_ratchet(self):
        files = {"A.swift": 'let name = "日本語"\n'}
        self.assertEqual(self.run_sample(files, allow={"ReForge/Sources/A.swift": ["日本語"]}).rules(), [])
        self.assertEqual(self.run_sample(files, baseline={"ReForge/Sources/A.swift": 1}).rules(), [])
        self.assertEqual(self.run_sample(files, baseline={"ReForge/Sources/A.swift": 0}).rules(), [1])

    def test_baseline_too_high_fails(self):
        self.assertEqual(self.run_sample({}, baseline={"ReForge/Sources/A.swift": 3}).rules(), [1])

    # 規則 2
    def test_unknown_id_and_argument_names(self):
        self.assertEqual(self.run_sample({"A.swift": 'ui("ui.button.nope")\n'}).rules(), [2])
        self.assertEqual(self.run_sample({"A.swift": 'ui("ui.band.remaining")\n'}).rules(), [2])
        self.assertEqual(self.run_sample({"A.swift": 'ui("ui.band.remaining", ["m": .int(1)])\n'}).rules(), [2])
        self.assertEqual(self.run_sample({"A.swift": 'ui("ui.band.remaining", ["n": .int(1), "m": .int(2)])\n'}).rules(), [2])
        self.assertEqual(self.run_sample({"A.swift": 'UIText.shared.string("ui.button.sleep", ["x": .int(1)])\n'}).rules(), [2])

    def test_select_branches_count_as_arguments(self):
        table = {**TABLE, "ui.body.tenths": "{k, select, 1 {一割} other {{k}割}}{n}"}
        files = {"Used.swift": USES_ALL, "A.swift": 'ui("ui.body.tenths", ["k": .string("1"), "n": .int(1)])\n'}
        sample = Sample(files, table=table)
        self.addCleanup(sample.close)
        self.assertEqual(sample.rules(), [])

    # 規則 3
    def test_unused_id_fails(self):
        sample = Sample({"Used.swift": 'ui("ui.button.sleep"); ui("ui.band.remaining", ["n": .int(1)])\n'})
        self.addCleanup(sample.close)
        self.assertEqual(sample.rules(), [3])

    def test_core_ids_outside_app_tables_are_not_checked(self):
        self.assertEqual(self.run_sample({}).rules(), [])  # core_ui.json の ui.daywrap.sep は使われていなくてよい

    # 規則 4
    def test_id_shape(self):
        table = {**TABLE, "ui.wide.name": "x", "ui.body.CamelCase": "y"}
        sample = Sample({"Used.swift": USES_ALL + 'ui("ui.wide.name"); ui("ui.body.CamelCase")\n'}, table=table)
        self.addCleanup(sample.close)
        self.assertEqual(sample.rules(), [4])

    def test_core_ids_used_by_the_app_are_exempt_from_the_shape_rule(self):
        table_files = {"Used.swift": USES_ALL, "A.swift": 'ui("ui.roster.confirm")\n'}
        sample = Sample(table_files)
        self.addCleanup(sample.close)
        (sample.root / "content/public/text/ja/core_ui.json").write_text(
            json.dumps({"language": "ja", "texts": {"ui.roster.confirm": "確定する"}}, ensure_ascii=False), encoding="utf-8")
        self.assertEqual(sample.rules(), [])

    # 規則 5
    def test_dynamic_id_fails(self):
        for code in ('ui("ui.tab." + name)', "ui(id)", 'ui("ui.tab.\\(name)")', 'UIText.shared.string(id)'):
            self.assertEqual(self.run_sample({"A.swift": code + "\n"}).rules(), [5], code)

    def test_function_definition_is_not_a_call(self):
        self.assertEqual(self.run_sample({"A.swift": "func ui(_ id: TextID) -> Text { Text(verbatim: id.rawValue) }\n"}).rules(), [])

    # 規則 6
    def test_text_concatenation_fails(self):
        self.assertEqual(self.run_sample({"A.swift": 'let t = ui("ui.button.sleep") + ui("ui.button.sleep")\n'}).rules(), [6])
        self.assertEqual(self.run_sample({"A.swift": 't = t + Text(verbatim: " ")\n'}).rules(), [6])

    def test_verbatim_with_japanese_and_interpolation_fails(self):
        self.assertEqual(self.run_sample({"A.swift": 'Text(verbatim: "・\\(x)")\n'}).rules(), [1, 6])

    def test_verbatim_with_only_interpolation_or_plain_ascii_passes(self):
        files = {"A.swift": 'Text(verbatim: "\\(a)/\\(b)"); Text(verbatim: "── \\(s)"); Text(verbatim: "+")\n'}
        self.assertEqual(self.run_sample(files).rules(), [])

    def test_unmoved_file_defers_rule_6_until_baseline_is_zero(self):
        files = {"A.swift": 'let a = Text("寝る") + Text("起きる")\n'}
        self.assertEqual(self.run_sample(files, baseline={"ReForge/Sources/A.swift": 2}).rules(), [])

    def test_nested_string_in_interpolation(self):
        files = {"A.swift": 'let s = "\\(x ?? "既定")"\n'}
        self.assertEqual(self.run_sample(files).rules(), [1])


class CheckNoReasonText(unittest.TestCase):
    def check(self, source, table=None):
        sample = Sample({"Game/FootCardView.swift": source}, table=table)
        self.addCleanup(sample.close)
        return reason.check(sample.root, ["ReForge/Sources/Game/FootCardView.swift"])

    def test_literal_is_still_checked(self):
        self.assertEqual(len(self.check('Text("足りない")\n')), 1)
        self.assertEqual(self.check('Text("寝る")\n'), [])

    def test_table_sentence_is_checked_by_id(self):
        table = {"ui.button.x": "材料が足りない", "ui.button.y": "あと {n} 個", "ui.button.z": "寝る"}
        self.assertEqual(len(self.check('ui("ui.button.x")\n', table)), 1)
        self.assertEqual(len(self.check('ui("ui.button.y", ["n": .int(1)])\n', table)), 1)
        self.assertEqual(self.check('ui("ui.button.z")\n', table), [])
        self.assertEqual(len(self.check('UIText.shared.string("ui.button.x")\n', table)), 1)


if __name__ == "__main__":
    unittest.main()
