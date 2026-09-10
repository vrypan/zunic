#!/usr/bin/env python3
"""Verify timed byte equality and display diagnostic-only policy differences."""
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from benchmark_contract import parse_dump, compare_outputs
from cases import CORPORA, DIAGNOSTICS


def main():
    snapshots = {name: (HERE / 'texts' / f'{name}.txt').read_bytes() for name in CORPORA + DIAGNOSTICS}
    commands = {
        'zunic': [str(HERE / 'zig-out/bin/zunic-strip-ansi-bench'), '--dump'],
        'rust': [str(HERE / 'target/release/rust-strip-ansi-bench'), str(HERE / 'texts'), '--dump'],
    }
    outputs = {peer: parse_dump(subprocess.check_output(command, text=True), snapshots, 'strip_ansi')
               for peer, command in commands.items()}
    compared = compare_outputs(outputs)
    failed = [name for name in CORPORA if not compared[name]['equal']]
    if failed:
        raise RuntimeError(f'Timed corpora differ: {failed}')
    print(f'All {len(CORPORA)} timed corpora produce identical bytes.')
    print('Diagnostic-only inputs (not timed):')
    for name in DIAGNOSTICS:
        print(f'{name}: input={snapshots[name]!r}')
        for peer in ('zunic', 'rust'):
            print(f'  {peer}: {bytes(outputs[peer][name])!r}')
    print('Unicode property versions: not applicable to these APIs; byte/control policies differ.')


if __name__ == '__main__':
    main()
