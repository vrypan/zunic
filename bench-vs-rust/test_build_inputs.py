"""Build preparation keeps cached and fetched corpora identical to the lockfile."""
import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import build_inputs


class CorpusBuildTests(unittest.TestCase):
    def prepare_fixture(self, root):
        (root / 'corpus.lock.json').write_text(json.dumps({
            'repository': 'owner/repo', 'revision': 'a' * 40, 'directory': 'benches/texts',
            'files': {'sample.txt': hashlib.sha256(b'exact bytes\n').hexdigest()},
        }))

    def test_missing_input_downloaded_then_reused(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.prepare_fixture(root)
            def fetch(command, **kwargs):
                self.assertIn('/' + 'a' * 40 + '/benches/texts/sample.txt', command[-3])
                Path(command[-1]).write_bytes(b'exact bytes\n')
            with patch.object(build_inputs, 'HERE', root), patch.object(build_inputs.subprocess, 'run', side_effect=fetch) as run:
                build_inputs.prepare(root / 'texts')
                build_inputs.prepare(root / 'texts')
                self.assertEqual(run.call_count, 1)
            self.assertEqual((root / 'texts/sample.txt').read_bytes(), b'exact bytes\n')

    def test_bad_download_is_not_installed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.prepare_fixture(root)
            def fetch(command, **kwargs):
                Path(command[-1]).write_bytes(b'wrong bytes')
            with patch.object(build_inputs, 'HERE', root), patch.object(build_inputs.subprocess, 'run', side_effect=fetch):
                with self.assertRaisesRegex(ValueError, 'downloaded corpus checksum mismatch'):
                    build_inputs.prepare(root / 'texts')
            self.assertEqual(list((root / 'texts').iterdir()), [])

    def test_modified_cache_is_preserved_and_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.prepare_fixture(root)
            (root / 'texts').mkdir()
            (root / 'texts/sample.txt').write_bytes(b'local edit')
            with patch.object(build_inputs, 'HERE', root), patch.object(build_inputs.subprocess, 'run') as run:
                with self.assertRaisesRegex(ValueError, 'corpus checksum mismatch'):
                    build_inputs.prepare(root / 'texts')
                run.assert_not_called()
            self.assertEqual((root / 'texts/sample.txt').read_bytes(), b'local edit')


if __name__ == '__main__':
    unittest.main()
