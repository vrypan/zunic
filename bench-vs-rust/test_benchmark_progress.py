"""Tests for the benchmark runners' single-line progress display."""
import contextlib
import io
import unittest

from benchmark_progress import BenchmarkProgress


class BenchmarkProgressTests(unittest.TestCase):
    def test_updates_one_line_and_finishes_completed(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            progress = BenchmarkProgress(2)
            progress.running("zunic-a")
            progress.advance()
            progress.running("rust-a")
            progress.advance()
            progress.finish()

        rendered = output.getvalue()
        self.assertEqual(rendered.count("\n"), 1)
        self.assertTrue(rendered.endswith("benchmark: completed (2/2)      \n"))

    def test_failure_is_the_final_update(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            progress = BenchmarkProgress(2)
            progress.running("zunic-a")
            progress.fail()

        rendered = output.getvalue()
        self.assertEqual(rendered.count("\n"), 1)
        self.assertTrue(rendered.endswith("benchmark: failed (0/2 completed)\n"))


if __name__ == "__main__":
    unittest.main()
