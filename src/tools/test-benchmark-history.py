import importlib.util
import json
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

spec = importlib.util.spec_from_file_location("history", Path(__file__).with_name("benchmark-history.py"))
history = importlib.util.module_from_spec(spec)
spec.loader.exec_module(history)

class HistoryTests(unittest.TestCase):
    def test_save_uses_selected_compiler_and_optimization(self):
        with tempfile.TemporaryDirectory() as tmp:
            for zig, optimize in (("zig", "ReleaseFast"), ("/custom/zig", "Debug")):
                with self.subTest(zig=zig, optimize=optimize):
                    argv = ["benchmark-history.py", "save", "--label", optimize]
                    if zig != "zig":
                        argv += ["--zig", zig, "--optimize", optimize]
                    argv += ["--", "--smoke"]
                    completed = history.subprocess.CompletedProcess([], 0, "", "")
                    with patch.object(history, "HISTORY", Path(tmp)), \
                         patch.object(history.sys, "argv", argv), \
                         patch.object(history.platform, "platform", return_value="fixture-os"), \
                         patch.object(history.platform, "processor", return_value="fixture-cpu"), \
                         patch.object(history, "git", return_value=""), \
                         patch.object(history, "digest_sources", return_value="fixture"), \
                         patch.dict(history.os.environ, {"ZUNIC_BENCHMARK_BUILD_ARGS": "-Dcpu=native"}), \
                         patch.object(history.subprocess, "run", return_value=completed) as run, \
                         patch.object(history.subprocess, "check_output", return_value="0.17.0\n") as version:
                        history.main()
                    expected = [zig, "build", "benchmark", f"-Doptimize={optimize}",
                                "-Dcpu=native", "--", "--smoke"]
                    self.assertEqual(run.call_args.args[0], expected)
                    version.assert_called_once_with([zig, "version"], text=True)
                    archive = next(Path(tmp).glob(f"*-{optimize}-*/metadata.json"))
                    metadata = json.loads(archive.read_text())
                    self.assertEqual(metadata["command"], expected)
                    self.assertEqual(metadata["zig"], "0.17.0")

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
