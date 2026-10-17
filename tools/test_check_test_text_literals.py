#!/usr/bin/env python3
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("check-test-text-literals.py")


class TestTextLiteralCheckTests(unittest.TestCase):
    def run_check(self, files, baseline):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for relative, body in files.items():
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(body, encoding="utf-8")
            baseline_path = root / "baseline.json"
            baseline_path.write_text(json.dumps(baseline), encoding="utf-8")
            return subprocess.run([sys.executable, str(SCRIPT), "--root", str(root), "--baseline", str(baseline_path)], text=True, capture_output=True)

    def test_marks_and_diagnostic_message_are_not_counted(self):
        result = self.run_check({"ReForgeCore/Tests/A/Example.swift": '''
            XCTAssertEqual(actual, "表の文") // ja-table
            XCTAssertTrue(value.contains("表の文")) // ja-ok: fixture content paired with an ID
            XCTAssertEqual(actual, expected, "失敗の文")
            // XCTAssertEqual(actual, "表の文")
        '''}, {})
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_increase_fails_and_decrease_reports(self):
        path = "ReForgeCore/Tests/A/Example.swift"
        bad = {path: 'XCTAssertEqual(actual, "表の文")'}
        result = self.run_check(bad, {path: 0})
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout.strip(), f"{path}: 1")
        result = self.run_check({}, {path: 1})
        self.assertEqual(result.returncode, 0)
        self.assertIn("lower baseline", result.stdout)

    def test_new_file_fails(self):
        path = "ReForgeTests/New.swift"
        result = self.run_check({path: 'XCTAssertEqual(actual, "表の文")'}, {})
        self.assertEqual(result.returncode, 1)
        self.assertIn(f"{path}: 1", result.stdout)


if __name__ == "__main__":
    unittest.main()
