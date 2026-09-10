"""Check the CLI of built benchmark programs without running timing loops."""
from pathlib import Path
import subprocess
import unittest

HERE = Path(__file__).resolve().parent
SUITES = {
    'rust-linebreak': ('line-break-diagnostic', 'diagnostic-rust/target/release/diagnostic'),
    'rust-normalize': ('zunic-normalize', 'target/release/unicode-normalization-zunic'),
    'rust-words': ('zunic-words-bench', 'target/release/unicode-words-bench'),
    'rust-wrap': ('zunic-wrap-bench', 'target/release/cellwidth-wrap-bench'),
    'rust-strip-ansi': ('zunic-strip-ansi-bench', 'target/release/rust-strip-ansi-bench'),
}


class ExecutableCliTests(unittest.TestCase):
    def test_help_and_explicit_modes(self):
        for suite, (zig, rust) in SUITES.items():
            for peer, relative in [('zunic', 'zig-out/bin/' + zig), ('rust', rust)]:
                with self.subTest(suite=suite, peer=peer):
                    binary = HERE / suite / relative
                    # Help must work independently of cwd and input availability.
                    for mode in [[], ['--help'], ['-h']]:
                        result = subprocess.run([str(binary), *mode], cwd='/', capture_output=True, text=True, timeout=5)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertIn('Usage:', result.stdout)
                        self.assertIn('--bench', result.stdout)
                        self.assertIn('--dump', result.stdout)
                        self.assertNotIn('protocol=1', result.stdout)
                        self.assertEqual(result.stderr, '')
                    bad_args = [['--unknown'], ['--dump', 'extra']] if peer == 'zunic' else [
                        ['/missing-corpus'], ['/missing-corpus', '--unknown'], ['/missing-corpus', '--dump', 'extra']]
                    for args in bad_args:
                        result = subprocess.run([str(binary), *args], cwd='/', capture_output=True, text=True, timeout=5)
                        self.assertNotEqual(result.returncode, 0)
                        self.assertNotIn('protocol=1', result.stdout)
                    corpus = HERE / suite / 'texts' if suite == 'rust-strip-ansi' else HERE / 'texts'
                    args = ['--dump'] if peer == 'zunic' else [str(corpus), '--dump']
                    result = subprocess.run([str(binary), *args], capture_output=True, text=True, timeout=10)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn('case=', result.stdout)
                    self.assertNotIn('Usage:', result.stdout)
                    self.assertNotIn('protocol=1', result.stdout)


if __name__ == '__main__':
    unittest.main()
