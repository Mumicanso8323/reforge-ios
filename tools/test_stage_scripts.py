#!/usr/bin/env python3
"""束を作るシェルの回帰の確かめ(macOS の bash 3.2 で動くこと・ストアの版だけ出さない言語を消すこと)。"""
import pathlib
import re
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONTENT_TOOLS = ROOT / "tools" / "content"
BASH4_ONLY = re.compile(r"\b(mapfile|readarray|declare\s+-A|local\s+-n|coproc)\b|\$\{[A-Za-z_]+(\^\^|,,)\}")


class StageScriptsTests(unittest.TestCase):
    def test_no_bash4_only_features(self):
        for script in sorted(CONTENT_TOOLS.glob("*.sh")):
            for number, line in enumerate(script.read_text().splitlines(), 1):
                if line.lstrip().startswith("#"):
                    continue
                self.assertIsNone(BASH4_ONLY.search(line), f"{script.name}:{number} bash 4 の機能: {line.strip()}")

    def test_trim_keeps_only_released(self):
        with tempfile.TemporaryDirectory() as tmp:
            text = pathlib.Path(tmp) / "text"
            for code in ["ja", "en", "ko", "zh-Hans", "ja-x"]:
                (text / code).mkdir(parents=True)
                (text / code / "a.json").write_text("{}")
            subprocess.run([str(CONTENT_TOOLS / "trim-public-languages.sh"), str(text), "ja"], check=True)
            self.assertEqual(sorted(p.name for p in text.iterdir()), ["ja"])

    def test_trim_missing_dir_is_noop(self):
        with tempfile.TemporaryDirectory() as tmp:
            subprocess.run([str(CONTENT_TOOLS / "trim-public-languages.sh"), str(pathlib.Path(tmp) / "none"), "ja"], check=True)

    def test_stage_trims_only_in_store_build(self):
        stage = (CONTENT_TOOLS / "stage.sh").read_text()
        store = stage.index('if [ "${REFORGE_STORE_BUILD:-}" = "1" ]; then')
        orelse = stage.index("else", store)
        call = stage.index("trim-public-languages.sh")
        self.assertTrue(store < call < orelse, "出さない言語を消すのはストアの版の枝の中だけ")
        self.assertEqual(stage.count("trim-public-languages.sh"), 1)


if __name__ == "__main__":
    unittest.main()
