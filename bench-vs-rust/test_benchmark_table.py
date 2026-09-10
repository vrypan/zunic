"""Tests for readable tables and the exact ±5% color thresholds."""
import os
import unittest
from unittest.mock import patch

from benchmark_table import Ratio, report, table


class BenchmarkTableTests(unittest.TestCase):
    HEADERS = ["Case", "Zunic µs", "Rust µs", "Rust/Zunic"]

    def test_plain_table_is_aligned_and_has_no_escapes(self):
        rendered = table(self.HEADERS, [["arabic", "10.000", "12.000", Ratio(1.2)]], color=False)
        self.assertIn("│ arabic │   10.000 │  12.000 │      1.20× │", rendered)
        self.assertNotIn("\033", rendered)

    def test_only_differences_greater_than_five_percent_are_colored(self):
        rows = [["fast", "1", "1", Ratio(1.051)],
                ["upper edge", "1", "1", Ratio(1.05)],
                ["lower edge", "1", "1", Ratio(0.95)],
                ["slow", "1", "1", Ratio(0.949)]]
        rendered = table(self.HEADERS, rows, color=True)
        self.assertEqual(rendered.count("\033[32m"), 1)
        self.assertEqual(rendered.count("\033[31m"), 1)

    def test_no_color_environment_disables_report_colors(self):
        with patch.dict(os.environ, {"FORCE_COLOR": "1", "NO_COLOR": "1"}, clear=False):
            rendered = report("Test", [("Op", self.HEADERS,
                                        [["x", "1", "2", Ratio(2)]])], [])
        self.assertNotIn("\033", rendered)

    def test_force_color_enables_report_colors_when_terminal_is_not_a_tty(self):
        environment = dict(os.environ)
        environment.pop("NO_COLOR", None)
        environment["FORCE_COLOR"] = "1"
        environment["TERM"] = "xterm-256color"
        with patch.dict(os.environ, environment, clear=True):
            rendered = report("Test", [("Op", self.HEADERS,
                                        [["x", "1", "2", Ratio(2)]])], [])
        self.assertIn("\033[32m", rendered)


if __name__ == "__main__":
    unittest.main()
