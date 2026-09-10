#!/usr/bin/env python3
"""Offline regressions for byte offsets and strict verification/report limits."""
import contextlib
import io
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import differential


def properties(changed=()):
    return {"wb": {ord(char): "ALetter" for char in changed}, "alpha": {}, "gc": {}}


class DifferentialTests(unittest.TestCase):
    def run_checker(self, text, zunic, rust, limit=12, changed=()):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "sample.txt").write_bytes(text.encode("utf-8"))
            binary = root / "peer"
            binary.touch()
            output = io.StringIO()
            with (
                patch.object(differential, "CORPORA", ("sample",)),
                patch.object(differential, "CORPUS_DIR", root),
                patch.object(differential, "ZUNIC_BIN", binary),
                patch.object(differential, "RUST_BIN", binary),
                patch.object(differential, "dump", side_effect=[{"sample": zunic}, {"sample": rust}]),
                patch.object(differential, "load_properties", side_effect=[properties(), properties(changed)]),
                patch("sys.argv", ["differential.py", "--verify", "--strict", "--max-report", str(limit)]),
                contextlib.redirect_stdout(output),
            ):
                result = differential.main()
            return result, output.getvalue()

    def test_boundary_byte_offset_after_multibyte_character(self):
        status, output = self.run_checker(
            "éαb", [(0, 2, False), (2, 5, True)], [(0, 5, False)], changed="α"
        )
        self.assertEqual(status, 0)
        self.assertIn("boundary at 2 (zunic only): U+03B1", output)
        self.assertIn("éαb", output)

    def test_flag_range_is_sliced_as_bytes(self):
        status, output = self.run_checker(
            "éαb", [(0, 2, False), (2, 4, True), (4, 5, True)],
            [(0, 2, False), (2, 4, False), (4, 5, True)], changed="α"
        )
        self.assertEqual(status, 0)
        self.assertIn("us=False 'α'", output)
        self.assertIn("U+03B1", output)

    def test_zero_report_limit_still_verifies_boundaries_and_flags(self):
        status, output = self.run_checker(
            "abc", [(0, 1, True), (1, 2, True), (2, 3, True)],
            [(0, 2, True), (2, 3, False)], limit=0
        )
        self.assertEqual(status, 1)
        self.assertIn("property changes: 2", output)
        self.assertNotIn("    boundary at", output)
        self.assertNotIn("    flag at", output)

    def test_unexplained_boundary_after_report_limit_fails(self):
        status, output = self.run_checker(
            "abc", [(0, 1, False), (1, 2, False), (2, 3, False)],
            [(0, 3, False)], limit=1, changed="b"
        )
        self.assertEqual(status, 1)
        self.assertIn("property changes: 1", output)
        self.assertNotIn("boundary at 2", output)

    def test_unexplained_flag_after_report_limit_fails(self):
        status, output = self.run_checker(
            "ab", [(0, 1, True), (1, 2, True)],
            [(0, 1, False), (1, 2, False)], limit=1, changed="a"
        )
        self.assertEqual(status, 1)
        self.assertIn("property changes: 1", output)
        self.assertNotIn("flag at 1", output)

    def test_identical_partitions_pass(self):
        segments = [(0, 2, True), (2, 4, True)]
        status, output = self.run_checker("éα", segments, segments, limit=0)
        self.assertEqual(status, 0)
        self.assertIn("status=identical", output)


if __name__ == "__main__":
    unittest.main()
