# Unicode 17 line-break machine

Regenerate with `python3 src/tools/generate-line-break-machine.py --write`.
Check reproducibility and the standard fixtures with
`python3 src/tools/test-line-break-machine.py`. No generator runs during a
normal Zig build; the package uses checked-in data and has no Python runtime
dependency. The implementation is authored from Zunic's Unicode 17 rules,
not copied Unicode 15 Rust table bytes.

## Construction and state identity

`generate-properties.py` and `line_break_semantics.py` share the deterministic
category key in `line_break_categories.py`. The property generator assigns IDs
in valid-scalar order and embeds each seven-bit ID in previously unused record
bits. The independent property test reconstructs and checks the ID for every
Unicode code point; the machine generator also rejects any ID/order mismatch.
The semantic compiler reads those records and enumerates actual scalar
categories. It retains raw class and East Asian width, relevant quote/
parenthesis predicates, SA-mark and EP-unassigned predicates, and the
U+2010/U+25CC exceptions. There are 69 categories. Embedding the category
does not increase the 32-bit property record or its 168 deduplicated blocks.

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
The transition table occupies 14,214 bytes; the budget is 32 KiB.

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
The direct iterator combines decision and consumption so it loads each entry
once. It decodes and buffers a following token only for contextual opcodes
3–7; final opcodes 0–2 stay on the compact path. Its private token carries only
an end offset and fused record. No runtime generic shadow state or partial-table
fallback remains.

## Scanner protocol and compatibility

Boundary queries are pure. Consumption advances once per scalar, whether or
not a boundary was queried. The fused scanner retains its existing classified
token buffer and `Cluster` interface; only LB25 may decode a second following
scalar. Existing scanner work-bound and view tests remain unchanged.

UTF-8 stepping uses an explicit validity-preserving decoder. It rejects stray
continuations, overlong sequences, surrogates and values above U+10FFFF, and
retains one-byte recovery for malformed input. Tests compare it with the
standard-library implementation for every valid scalar, leading byte and
truncation length, explicit malformed classes and randomized inputs.

`line_break.State` is the generated machine state. The old branch-based State,
its methods/fields, `ActiveState`, and the `-Dline-break-engine` build selector
have been removed. This intentionally breaks low-level compatibility; recover
historical implementations from Git commit `2620ac3` if needed.
View signatures, laziness, independent iterators and allocation behavior are
unchanged. There is one production engine and no retained generic test engine.

The wrapper's general method is isolated from its inline ASCII dispatch.
This changes compiler specialization, not the fitting algorithm or Cluster
seam. The previous shared body caused repeatable ASCII regressions as the
scanner's inlining cost changed. Measurements remain under `private/benchmarks`.

## Verification

The Python verifier checks all 16,672 pinned LineBreakTest cases (52,389
scalar boundaries), mandatory hard-break precedence separately, reachability
witnesses and total successor/action ranges. Zig transition tests independently
select all 69 categories from real records, enumerate all pairs/triples,
check seeded longer streams and malformed byte tails, repeat queries, and
consume copied state without querying. Run them independently with
`zig build line-break-tests`.

`bench-vs-rust/rust-linebreak/verify-semantic.zig` checks full ordered boundary
streams between Iterator and direct machine State on all eight real corpora.
These and the exhaustive Zig protocol tests check integration consistency,
not independent rule correctness. The pinned Unicode fixtures remain the
standard-based checks; generator tests also validate compilation/minimization.
Rust remains a throughput peer, not the Unicode 17 correctness oracle.

Known inherited limitation: SA Mn/Mc characters resolve to CM, but the current
LB9/base-inheritance checks still use raw CM/ZWJ classes. For example,
`a\u{0e31}` incorrectly permits the boundary at byte 1, inherited from the removed engine.
The pinned fixtures do not expose this case. This needs a separate correctness
fix; passing fixtures and protocol tests is not exhaustive conformance.
