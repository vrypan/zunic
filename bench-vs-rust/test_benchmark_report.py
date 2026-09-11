"""The same summary parser and reporters accept every benchmark suite."""
import json
import tempfile
import unittest
from pathlib import Path

from benchmark_report import SCHEMA, create_summary, markdown_report, terminal_report, load_summary, validate_summary


def row(ns, units=2):
    return {"bytes": 100, "units": units, "iterations": 10, "median_ns": ns,
            "mad_ns": 1, "checksum": 42, "samples_ns": [ns] * 15}


class BenchmarkReportTests(unittest.TestCase):
    def summary(self, suite):
        operation = {"normalize": "nfc", "words": "bounds", "wrap": "full", "linebreak": "opportunities", "strip_ansi": "strip", "width": "width"}[suite]
        pair = {"name": "a", "order": ("zunic", "rust"),
                "zunic": {"sample": {operation: row(100)}},
                "rust": {"sample": {operation: row(120)}}}
        return create_summary(
            suite=suite, title=suite.title(), label="test", pairs=[pair],
            comparisons=[{"id": operation, "label": operation, "zunic": operation, "rust": operation}],
            peers={"zunic": {"name": "Zunic", "unicode": "16.0.0"},
                   "rust": {"name": "Rust library", "unicode": "17.0.0"}},
            contract={"input": "bytes", "consumption": "test"},
            outputs={"sample": {"equal": True, "zunic_count": 2, "rust_count": 2}},
            operation_outputs={operation: {"sample": {"equal": True, "zunic_count": 2, "rust_count": 2}}},
            notes=[], environment={}, provenance={})

    def test_all_suites_share_one_schema_and_reporters(self):
        for suite in ("normalize", "words", "wrap", "linebreak", "strip_ansi", "width"):
            with self.subTest(suite=suite):
                summary = json.loads(json.dumps(self.summary(suite)))
                self.assertEqual(summary["schema"], SCHEMA)
                self.assertIn("1.20×", terminal_report(summary))
                self.assertIn("1.20×", markdown_report(summary))

    def test_summary_round_trips_as_json(self):
        summary = self.summary("words")
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "summary.json"
            path.write_text(json.dumps(summary))
            self.assertEqual(json.loads(path.read_text()), json.loads(json.dumps(summary)))

    def test_operation_verdicts_are_separate_in_both_reporters(self):
        summary = self.summary('normalize')
        comparison = summary['comparisons'][0]
        comparison.update(id='nfc', label='NFC')
        second = dict(comparison, id='nfd', label='NFD')
        summary['comparisons'].append(second)
        summary['operation_outputs'] = {
            'nfc': {'sample': {'equal': True, 'zunic_count': 2, 'rust_count': 2}},
            'nfd': {'sample': {'equal': False, 'zunic_count': 2, 'rust_count': 2}},
        }
        for render in (markdown_report, terminal_report):
            result = render(summary)
            self.assertIn('same', result)
            self.assertIn('diff', result)
            self.assertIn('NFC: Exact outputs matched: sample.', result)
            self.assertIn('NFD: Exact outputs matched: none. Exact outputs differed: sample.', result)

    def test_missing_legacy_evidence_is_unverified_not_diff(self):
        summary = self.summary('wrap')
        del summary['operation_outputs']
        for render in (markdown_report, terminal_report):
            self.assertIn('unverified', render(summary))
            self.assertNotIn('Exact outputs matched: sample.', render(summary))

    def test_operation_counts_and_completeness_are_checked(self):
        for mutation in ('count', 'missing'):
            summary = self.summary('wrap')
            if mutation == 'count':
                summary['operation_outputs']['full']['sample']['zunic_count'] = 3
            else:
                summary['operation_outputs']['full'] = {}
            with self.assertRaises(ValueError):
                validate_summary(summary)

    def test_legacy_archive_recovered_without_changing_summary(self):
        from benchmark_contract import signature
        summary = self.summary('wrap')
        del summary['operation_outputs']
        summary['comparisons'] = [
            {'id': 'full', 'label': 'Full', 'zunic': 'zunic_iterate', 'rust': 'textwrap_first_fit'},
            {'id': 'viewport', 'label': 'Viewport', 'zunic': 'zunic_first24', 'rust': 'textwrap_first_fit_take24'},
        ]
        source = b'a\n' * 25
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            (base / 'texts').mkdir()
            (base / 'texts/sample.txt').write_bytes(source)
            for peer in ('zunic', 'rust'):
                records = ['61'] * 25 + ([''] if peer == 'rust' else [])
                rows = {}
                for comparison in summary['comparisons']:
                    selected = records[:24] if comparison['id'] == 'viewport' else records
                    units, checksum = signature(selected, 'wrap')
                    rows[comparison[peer]] = dict(row(100, units), bytes=len(source), checksum=checksum)
                summary['pairs'][0]['results'][peer]['sample'] = rows
                (base / (peer + '-before.dump')).write_text(
                    'case=sample input=' + source.hex() + '\n' + ''.join('L ' + record + '\n' for record in records))
            path = base / 'summary.json'
            original = json.dumps(summary)
            path.write_text(original)
            loaded = load_summary(path)
            self.assertFalse(loaded['operation_outputs']['full']['sample']['equal'])
            self.assertTrue(loaded['operation_outputs']['viewport']['sample']['equal'])
            self.assertEqual(path.read_text(), original)
            summary['pairs'][0]['results']['rust']['sample']['textwrap_first_fit_take24']['checksum'] += 1
            path.write_text(json.dumps(summary))
            with self.assertRaisesRegex(ValueError, 'timed result'):
                load_summary(path)


if __name__ == "__main__":
    unittest.main()
