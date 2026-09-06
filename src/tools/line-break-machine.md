# Unicode 16 line-break machine

Regenerate with `python3 src/tools/generate-line-break-machine.py --write`.
Check reproducibility and the standard fixtures with
`python3 src/tools/test-line-break-machine.py`. No generator runs during a
normal Zig build; the package uses checked-in data and has no Python runtime
dependency. The implementation is authored from Zunic's Unicode 16 rules,
not copied Unicode 15 Rust table bytes.

## Construction and state identity

`line_break_semantics.py` reads the checked-in fused property records and
enumerates actual scalar categories. It retains raw class and East Asian
width, relevant quote/parenthesis predicates, SA-mark and EP-unassigned
predicates, and the U+2010/U+25CC exceptions. There are 68 categories.
The compact category key is proven injective across those categories.

Starting at SOT, breadth-first reachability follows `consume` for every
category, recording a scalar witness for each of 215 reachable histories.
History retains effective and raw previous classes, base predicates surviving
CM/ZWJ, space-run contexts, quote/SOT facts, numeric context, Hebrew/hyphen
context, Brahmic virama context, and RI parity. It does not enumerate the
Cartesian product of all history flags.

Each history/category pair has a decision signature over all observable
lookahead combinations. Initial state partitions share the same complete
output rows. Successor-partition refinement continues until stable: states
are merged only when both outputs and future successor equivalence agree.
The resulting 103-state machine uses a one-byte state ID and u16 entries:
low byte is successor, high byte is decision opcode. SOT is state zero.
Transitions plus category map occupy 14,392 bytes; the budget is 32 KiB.

## Rule mapping and precedence

`decision` evaluates these groups in standard precedence order. It is an
offline compiler function, not a fallback in the runtime loop.

| Rule group | Retained facts / implementation |
| --- | --- |
| LB1 | Raw class resolution; SA marks versus letters; CM/ZWJ inheritance |
| LB2–3 | SOT row prohibits the initial boundary; iterator emits mandatory EOT, including empty input |
| LB4–8a | Raw hard classes and CRLF; ZW SP* state; raw ZWJ |
| LB9–10 | Effective class and retained base predicates through ignored marks |
| LB11–14 | WJ/GL/closing classes and OP SP* context |
| LB15a–d | Initial quote/SP context, final-quote follower, SP–IS–NU lookahead |
| LB16–18 | CL/CP SP*, B2 SP*, then ordinary space opportunities |
| LB19–19a | Quote kind, neighboring East Asian widths, quote-at-SOT |
| LB20–22 | CB, initial hyphen, Hebrew/hyphen, SY–HL, inseparables |
| LB23–25 | Alphabetic/numeric/affix classes, numeric run and closing contexts, bounded second lookahead |
| LB26–28 | Hangul pairs and affixes; alphabetic pairs |
| LB28a | Aksara and dotted-circle predicates, virama context, following VF |
| LB29–30 | IS–alphabetic; retained OP30/CP30 predicates |
| LB30a–b | RI parity; emoji base/modifier and EP-unassigned predicate |
| LB31 | Allowed when no earlier rule applies |

The runtime has eight opcodes: prohibited, allowed, mandatory, and five
bounded handlers (LB15c, LB15b, LB25, LB19a, LB28a). The generator checks the
entire output signature of every handler; new patterns fail generation.
No runtime generic shadow state or partial-table fallback remains.

## Scanner protocol and compatibility

Boundary queries are pure. Consumption advances once per scalar, whether or
not a boundary was queried. The fused scanner retains its existing classified
token buffer and `Cluster` interface; only LB25 may decode a second following
scalar. Existing scanner work-bound and lens tests remain unchanged.

`line_break.State` retains its public fields and methods as an independent,
branch-based compatibility implementation. `Iterator.state` now has the
selected backend's representation; concrete field layout is not preserved.
Lens signatures, laziness, independent iterators and allocation behavior are
unchanged. The build selector is `-Dline-break-engine=generic|machine`.

The wrapper's general method is isolated from its inline ASCII dispatch.
This changes compiler specialization, not the fitting algorithm or Cluster
seam. The previous shared body caused repeatable ASCII regressions as the
scanner's inlining cost changed. Measurements remain under `private/benchmarks`.

## Verification

The Python verifier checks all 16,672 pinned LineBreakTest cases (52,389
scalar boundaries), mandatory hard-break precedence separately, reachability
witnesses and total successor/action ranges. Zig transition tests independently
select all 68 categories from real records, enumerate all pairs/triples,
check seeded longer streams and malformed byte tails, repeat queries, and
consume copied state without querying. Run them independently with
`zig build line-break-tests -Dline-break-engine=machine`.

Private `rust-comparison/verify-semantic.zig` compares full ordered boundary
streams with the independent generic State over all eight real corpora.
Rust remains a throughput peer, not the Unicode 16 correctness oracle.

Known inherited limitation: SA Mn/Mc characters resolve to CM, but the current
LB9/base-inheritance checks still use raw CM/ZWJ classes. For example,
`a\u{0e31}` incorrectly permits the boundary at byte 1 in both engines.
The pinned fixtures do not expose this case. This needs a separate correctness
fix; passing fixtures and reference differentials is not exhaustive conformance.
