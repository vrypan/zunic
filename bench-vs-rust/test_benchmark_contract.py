"""Offline tests for benchmark validation independent of either timed library."""
import unittest
from benchmark_contract import parse_dump, parse_timing, signature, check_rows, require_contract, compare_outputs, compare_operations


class ContractTests(unittest.TestCase):
    def test_raw_input_identity_including_multibyte_text(self):
        dump = 'case=x input=c3a961\ncase=x bytes=3\nS 0 2 1\nS 2 3 0\n'
        self.assertEqual(parse_dump(dump, {'x': 'éa'.encode()}, 'words')['x'], [(0, 2, 1), (2, 3, 0)])
        with self.assertRaisesRegex(ValueError, 'input differs'):
            parse_dump(dump, {'x': b'abc'}, 'words')

    def test_missing_and_broken_partitions_rejected(self):
        for dump in ['', 'case=x input=6162\nS 0 1 1\n', 'case=x input=6162\nS 1 2 1\n']:
            with self.assertRaises(ValueError):
                parse_dump(dump, {'x': b'ab'}, 'words')

    def test_old_prevalidated_contract_rejected(self):
        with self.assertRaises(ValueError):
            require_contract('protocol=1 input=prevalidated consumption=range_checksum_v1', 'words')
        require_contract('protocol=1 input=bytes consumption=range_checksum_v1', 'words')

    def test_common_timing_protocol(self):
        samples = list(range(1, 16))
        text = ("protocol=1 suite=words peer=rust samples=15 calibration_ms=50 "
                "input=bytes consumption=range_checksum_v1\n"
                f"case=x op=bounds raw_samples={samples}\n"
                "case=x op=bounds bytes=3 units=2 iterations=9 ns=8 mad=4 checksum=17\n")
        rows = parse_timing(text, suite="words", peer="rust", cases=("x",), operations=("bounds",))
        self.assertEqual(rows["x"]["bounds"]["samples_ns"], samples)
        self.assertEqual(rows["x"]["bounds"]["units"], 2)

    def test_timed_word_checksum_and_filter(self):
        outputs = {'x': [(0, 2, 1), (2, 3, 0)]}
        check_rows({'x': {'us_words': {'units': 1, 'checksum': 2}}}, outputs, 'words')
        with self.assertRaisesRegex(ValueError, 'timed result'):
            check_rows({'x': {'us_words': {'units': 1, 'checksum': 3}}}, outputs, 'words')

    def test_wrap_viewport_hashes_only_selected_lines(self):
        outputs = {'x': ['61'] * 25}
        count, checksum = signature(outputs['x'][:24], 'wrap')
        check_rows({'x': {'zunic_first24': {'units': count, 'checksum': checksum}}}, outputs, 'wrap')
        self.assertNotEqual(signature(['61', '62'], 'wrap'), signature(['6162'], 'wrap'))

    def test_linebreak_status_contributes(self):
        self.assertEqual(signature([(3, 1), (9, 2)], 'linebreak'), (2, ((3 * 31 + 1) * 31 + 9) * 31 + 2))
        dump = 'case=x input=61\ncase=x stream=1:mandatory,\n'
        parsed = parse_dump(dump, {'x': b'a'}, 'linebreak')
        check_rows({'x': {'opportunities_only': {'units': 1, 'checksum': 33}}}, parsed, 'linebreak')

    def test_different_outputs_reported_without_rejection(self):
        cross = compare_outputs({'zunic': {'x': [(0, 2, 1)]}, 'rust': {'x': [(0, 1, 1), (1, 2, 1)]}})
        self.assertFalse(cross['x']['equal'])

    def test_strip_byte_output_including_empty_and_invalid_utf8(self):
        dump = 'case=x input=1b5b6d\nB \ncase=y input=ff61\nB ff61\n'
        outputs = parse_dump(dump, {'x': b'\x1b[m', 'y': b'\xffa'}, 'strip_ansi')
        self.assertEqual(outputs, {'x': [], 'y': [255, 97]})
        self.assertEqual(signature([], 'strip_ansi'), (0, 0xcbf29ce484222325))
        self.assertEqual(signature([97], 'strip_ansi'), (1, 0xaf63dc4c8601ec8c))
        count, checksum = signature(outputs['y'], 'strip_ansi')
        check_rows({'y': {'rust_reuse': {'units': count, 'checksum': checksum}}}, outputs, 'strip_ansi')
        with self.assertRaisesRegex(ValueError, 'timed result'):
            check_rows({'y': {'rust_reuse': {'units': count, 'checksum': checksum + 1}}}, outputs, 'strip_ansi')

    def test_strip_dump_requires_one_byte_output_per_case(self):
        for dump in ('case=x input=61\n', 'case=x input=61\nB \nB \n'):
            with self.assertRaises(ValueError):
                parse_dump(dump, {'x': b'a'}, 'strip_ansi')

    def test_operation_comparison_uses_viewport_not_whole_document(self):
        outputs = {'zunic': {'x': ['61'] * 25}, 'rust': {'x': ['61'] * 25 + ['']}}
        comparisons = [
            {'id': 'full', 'zunic': 'zunic_iterate', 'rust': 'textwrap_first_fit'},
            {'id': 'viewport', 'zunic': 'zunic_first24', 'rust': 'textwrap_first_fit_take24'},
        ]
        result = compare_operations(outputs, 'wrap', comparisons)
        self.assertFalse(result['full']['x']['equal'])
        self.assertEqual(result['viewport']['x'], {'equal': True, 'zunic_count': 24, 'rust_count': 24})
        outputs['rust']['x'][0] = '6120'
        self.assertFalse(compare_operations(outputs, 'wrap', comparisons)['viewport']['x']['equal'])

    def test_operation_comparison_filters_words_and_ignores_unconsumed_flags(self):
        comparisons = [
            {'id': 'bounds', 'zunic': 'zunic_word_bounds', 'rust': 'us_word_bounds'},
            {'id': 'words', 'zunic': 'zunic_words', 'rust': 'us_words'},
        ]
        outputs = {'zunic': {'x': [(0, 1, 1), (1, 3, 0)]},
                   'rust': {'x': [(0, 1, 1), (1, 2, 0), (2, 3, 0)]}}
        result = compare_operations(outputs, 'words', comparisons)
        self.assertFalse(result['bounds']['x']['equal'])
        self.assertTrue(result['words']['x']['equal'])
        outputs['rust']['x'] = [(0, 1, 0), (1, 3, 0)]
        result = compare_operations(outputs, 'words', comparisons)
        self.assertTrue(result['bounds']['x']['equal'])
        self.assertFalse(result['words']['x']['equal'])


if __name__ == '__main__':
    unittest.main()
