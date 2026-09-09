# Wrap implementation decisions

[API](README.md) · [Architecture](../architecture.md)

## Share the scan

The general wrapper uses [scan.zig](../../src/layout/scan.zig) to find graphemes,
measure them, and check line-break opportunities together. These operations
need many of the same character properties. Sharing the scan avoids decoding
and looking up the same character separately for each operation.

The scanner keeps at most two tokens. Most characters are decoded once;
one numeric line-break rule can inspect a second following character again.
The tests check that total decoding stays below twice the character count,
regardless of line width or how many lines the caller requests.

## Keep a fitting break without starting over

[wrap.zig](../../src/layout/wrap.zig) remembers the most recent fitting break and
the columns measured since it. When a later cluster overflows, the wrapper can
return that saved line and carry the already measured tail to the next line.
It does not restart the general scanner at the saved break. At most one extra
line is held for the next call.

## Use simpler rules only for checked ASCII input

On the first `next()`, a detector checks the input for one of two supported
ASCII subsets. Letter-only input can be split by byte count because every byte
is a one-column grapheme. A broader subset includes spaces, digits, hard breaks,
and selected punctuation. Its simpler loop handles spaces and the remaining
numeric punctuation exception directly.

Characters such as `-`, `/`, parentheses, `$`, `%`, and `+` are excluded from
that broader shortcut because their line-break rules need more context. Any
unsupported byte selects the general scanner. The shortcut is checked against
the full rules in [exhaustive tests](../../src/wrap_exhaustive_test.zig).

The detector can use 16-byte vector checks on supported CPUs. This first scan
is a tradeoff: it saves rule work on ASCII input but may inspect the whole input
even when only one line is requested. The simple ASCII loop can also revisit a
tail after a saved break; the no-rewind design above describes the general path.

The general path is kept in a separate `noinline` function so changes to its
size do not prevent the compiler from optimizing the small ASCII path.

## Compile the line-break rules into a table

The production line-break engine uses a generated table. Its generator starts
with reachable histories and merges only histories that give the same current
and future decisions. Most entries directly say allowed, prohibited, or
mandatory. A few request a small amount of lookahead.

The table is generated ahead of time and checked into the source tree; normal
builds do not run Python. [The generator notes](../../src/tools/line-break-machine.md)
document the state counts, rule mapping, and checks in detail. There is one
production engine; the old `-Dline-break-engine` selector is no longer available.

## Known limitation

Some marks in the UAX #14 `SA` class are resolved as combining marks, but the
current inheritance check still examines their original class. For example,
the low-level engine incorrectly permits a break inside `"a\u{0e31}"` at
byte 1. The wrapper also requires a grapheme boundary, so a low-level break
opportunity does not automatically become a wrapped-line boundary.

This is an inherited correctness issue, not an intentional speed shortcut.
Passing the pinned line-break fixtures does not cover every possible input.

See [scanner tests](../../src/scan_test.zig),
[wrap tests](../../src/wrap_test.zig), and
[regression tests](../../src/wrap_regression_test.zig) for checks of the shared
scan, output slices, and work limits.
