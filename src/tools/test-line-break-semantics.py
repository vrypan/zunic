#!/usr/bin/env python3
"""Check the semantic compiler against the pinned standard's full fixture."""
from pathlib import Path

from line_break_semantics import Category, History, categories, compile_machine, consume, decision, HARD


def main():
    fixture = Path(__file__).resolve().parents[1] / "data/LineBreakTest-17.0.0.txt"
    cases, points = [], set()
    for number, line in enumerate(fixture.read_text().splitlines(), 1):
        tokens = line.split("#", 1)[0].split()
        if not tokens:
            continue
        scalars = tuple(int(x, 16) for x in tokens[1::2])
        boundaries = tuple(x == "÷" for x in tokens[::2])
        cases.append((number, scalars, boundaries))
        points.update(scalars)
    inputs, witnesses, selected = categories(points)
    states, paths, groups, rows, signatures, lookahead = compile_machine(inputs)
    input_id = {category: i for i, category in enumerate(inputs)}
    lookahead_id = {key: i for i, key in enumerate(lookahead)}
    boundaries_checked = 0
    for number, scalars, expected in cases:
        state, machine_state = None, groups[0]
        stream = [selected[cp] for cp in scalars]
        for i, category in enumerate(stream):
            following = stream[i + 1] if i + 1 < len(stream) else None
            second_nu = i + 2 < len(stream) and stream[i + 2].raw == "nu"
            result = decision(state, category, following, second_nu)
            n = Category(following.raw, wide=following.wide) if following else None
            look = lookahead_id[n, second_nu if following else False]
            successor, signature = rows[machine_state][input_id[category]]
            actual = signatures[signature][look]
            assert actual == result, (number, i, "minimization changed output")
            assert bool(actual) == expected[i], (number, i, scalars, expected, actual)
            state = consume(state or History(), category, first=state is None)
            machine_state = successor
            boundaries_checked += 1
        assert decision(state, None) == 2 and expected[-1]
    # The fixture records allowed/mandatory with one marker. Pin the stronger
    # API separately, including empty text and hard-break precedence over WJ.
    assert decision(None, None) == 2
    for hard in HARD:
        state = consume(History(), Category(hard), first=True)
        assert decision(state, Category("wj")) == 2
        assert decision(state, Category("lf")) == (0 if hard == "cr" else 2)
    # Every stored state has a real scalar witness and every edge is total.
    for expected_state, path in zip(states[1:], paths[1:]):
        state = None
        for ci in path:
            state = consume(state or History(), inputs[ci], first=state is None)
        assert state == expected_state
    assert all(len(row) == len(inputs) for row in rows)
    assert all(0 <= target < len(rows) and 0 <= action < len(signatures)
               for row in rows for target, action in row)
    print(f"Unicode 17: {len(cases)} cases, {boundaries_checked} scalar boundaries passed")
    print(f"Reachability/minimization: {len(states)} histories -> {len(rows)} states; {len(inputs)} categories; {len(signatures)} actions")


if __name__ == "__main__":
    main()
