#!/usr/bin/env python3
"""Test archived report loading without building or running benchmarks."""
import contextlib
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("uucode_benchmark", Path(__file__).with_name("benchmark.py"))
benchmark = importlib.util.module_from_spec(spec)
spec.loader.exec_module(benchmark)


class ReportTests(unittest.TestCase):
    def fixture(self, schema):
        return {
            "schema": schema, "title": "Fixture", "label": "fixture", "pair_count": 1,
            "peers": {peer: {"unicode": "17.0.0"} for peer in ("zunic", "uucode")},
            "operations": ["utf8"], "cases": ["english"], "notes": [],
            "operation_outputs": {"utf8": {"english": {"equal": True}}},
            "pairs": [{"results": {
                peer: {"english": {"utf8": {"median_ns": ns, "units": 10}}}
                for peer, ns in (("zunic", 1000), ("uucode", 2000))
            }}],
        }

    def render(self, summary):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "summary.json"
            path.write_text(json.dumps(summary))
            output = io.StringIO()
            with patch.object(benchmark.sys, "argv", ["benchmark.py", "--report", str(path)]), \
                 patch.object(benchmark, "benchmark", side_effect=AssertionError("unexpected benchmark run")), \
                 contextlib.redirect_stdout(output):
                self.assertEqual(benchmark.main(), 0)
            return output.getvalue()

    def test_current_schema_round_trip(self):
        summary = self.fixture(benchmark.SUMMARY_SCHEMA)
        rendered = self.render(summary)
        self.assertEqual(rendered, benchmark.report(summary, True))
        self.assertIn("| english | 1.000 | 2.000 | 2.00× | 10/10 | same |", rendered)

    def test_legacy_schemas_remain_readable(self):
        for version in range(1, 8):
            with self.subTest(version=version):
                self.render(self.fixture(f"zunic-uucode-benchmark/v{version}"))

    def test_unknown_or_missing_schema_is_rejected(self):
        for schema in (None, "zunic-uucode-benchmark/v999", "unrelated/v8"):
            with self.subTest(schema=schema), self.assertRaisesRegex(ValueError, "unsupported summary schema"):
                self.render(self.fixture(schema))


if __name__ == "__main__":
    unittest.main()
