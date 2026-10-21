#!/usr/bin/env python3
"""tools/check-time-tint-shots.py の確かめ(合成の要約で)。python3 tools/test_check_time_tint_shots.py"""
import importlib.util
import json
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("check_time_tint_shots", os.path.join(HERE, "check-time-tint-shots.py"))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def shots(override=None):
    override = override or {}
    out = []
    for i, p in enumerate(mod.POINTS):
        for look in mod.LOOKS:
            e = {"point": p, "appearance": look, "outside": "o", "tabs": "t", "map": f"m{i}",
                 "redFraction": 0, "litFraction": 0.2 if p != "night" else 0.0,
                 "dayBar": p != "night", "dayBarLabelHasNoDigits": True}
            e.update(override.get((p, look), {}))
            out.append(e)
    return out


class CheckTimeTintShotsTests(unittest.TestCase):
    def run_check(self, entries, *flags):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump(entries, f)
            path = f.name
        try:
            return mod.main(["x", *flags, path])
        finally:
            os.unlink(path)

    def test_good_summary_passes(self):
        self.assertEqual(self.run_check(shots()), 0)
        self.assertEqual(self.run_check(shots(), "--map-only"), 0)

    def test_blank_map_fails_even_when_hashes_differ(self):
        blank = {(p, look): {"litFraction": 0.0} for p in ["dawn", "noon", "evening"] for look in mod.LOOKS}
        self.assertEqual(self.run_check(shots(blank), "--map-only"), 1)

    def test_missing_lit_fraction_fails(self):
        entries = shots()
        for e in entries:
            e.pop("litFraction")
        self.assertEqual(self.run_check(entries, "--map-only"), 1)

    def test_map_only_ignores_outside_hashes(self):
        changed = {("noon", "light"): {"outside": "other", "tabs": "other"}}
        self.assertEqual(self.run_check(shots(changed)), 1)
        self.assertEqual(self.run_check(shots(changed), "--map-only"), 0)

    def test_same_map_at_two_points_fails(self):
        same = {("noon", look): {"map": "m0"} for look in mod.LOOKS}
        self.assertEqual(self.run_check(shots(same), "--map-only"), 1)


if __name__ == "__main__":
    unittest.main(verbosity=0, argv=sys.argv[:1])
