import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("history", Path(__file__).with_name("benchmark-history.py"))
history = importlib.util.module_from_spec(spec)
spec.loader.exec_module(history)

class HistoryTests(unittest.TestCase):
    def test_summarize_median_and_spread(self):
        samples = {("x", "wrap", "full"): [
            {"elapsed_ns": "10", "checksum": "7"}, {"elapsed_ns": "20", "checksum": "7"}, {"elapsed_ns": "30", "checksum": "7"},
        ]}
        value = history.summarize(samples)["x/wrap/full"]
        self.assertEqual(20, value["median_ns"])
        self.assertEqual(1, value["spread"])
    def test_label_policy(self):
        self.assertTrue(history.SAFE_LABEL.fullmatch("before-007"))
        self.assertFalse(history.SAFE_LABEL.fullmatch("../unsafe"))
    def test_parse_samples(self):
        header, samples = history.parse_samples("zunic-benchmark harness_version=2\ncase=x operation=wrap traversal=full elapsed_ns=1 checksum=2\n")
        self.assertEqual("2", header["harness_version"])
        self.assertIn(("x", "wrap", "full"), samples)

if __name__ == "__main__":
    unittest.main()
