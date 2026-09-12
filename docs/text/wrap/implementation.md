# Wrap implementation decisions

[API](README.md) · [Architecture](../../internals/README.md)

## Share the scan

The general wrapper uses [scan.zig](../../../src/layout/scan.zig) to find graphemes,
measure them, and check line-break opportunities together. These operations
need many of the same character properties. Sharing the scan avoids decoding
and looking up the same character separately for each operation.

The scanner keeps at most two tokens. Most characters are decoded once;
one numeric line-break rule can inspect a second following character again.
The tests check that total decoding stays below twice the character count,
regardless of line width or how many lines the caller requests.

## Keep a fitting break without starting over

[wrap.zig](../../../src/layout/wrap.zig) remembers the most recent fitting break and
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
unsupported byte selects the mixed path described below. The shortcut is checked against
the full rules in [exhaustive tests](../../../src/wrap_exhaustive_test.zig).

The detector can use 16-byte vector checks on supported CPUs. This first scan
is a tradeoff: it saves rule work on ASCII input but may inspect the whole input
even when only one line is requested. The simple ASCII loop can also revisit a
tail after a saved break; the no-rewind design above describes the general path.

The general path is kept in a separate `noinline` function so changes to its
size do not prevent the compiler from optimizing the small ASCII path.

## Emit an ASCII line directly when it fits

The mixed path checks for a complete ASCII line at a clean line start. If its
measured width fits, it can return the line without computing internal break
opportunities. This accepts punctuation and tabs excluded from the paragraph
shortcut above. C0 controls have zero width; DEL and non-ASCII bytes select
the general scanner. CRLF is consumed as one terminator, and returned slices
exclude hard terminators as on the general path.

This check is used only when no candidate break, carried columns, or pending
line must be preserved. After returning a complete line, the scanner is marked
stale. If a later line needs the general path, the scanner restarts at that
hard-break boundary, where earlier line-break context no longer applies.
The check stops as soon as the measured width exceeds the limit and falls
back to the full rules. This bounds repeated probes when overflowing words
produce several wrapped lines within one physical line. Tests count the probe's
byte reads separately from the general scanner's decodes.
With `wrap-fast-path=off`,
the whole-line check still runs scalarly; only its vector scan is disabled.

## Compile the line-break rules into a table

The production line-break engine uses a generated table. Its generator starts
with reachable histories and merges only histories that give the same current
and future decisions. Most entries directly say allowed, prohibited, or
mandatory. A few request a small amount of lookahead.

The table is generated ahead of time and checked into the source tree; normal
builds do not run Python. [The generator notes](../../../src/tools/line-break-machine.md)
document the state counts, rule mapping, and checks in detail. There is one
production engine; the old `-Dline-break-engine` selector is no longer available.

See [scanner tests](../../../src/scan_test.zig),
[wrap tests](../../../src/wrap_test.zig), and
[regression tests](../../../src/wrap_regression_test.zig) for checks of the shared
scan, output slices, and work limits.

## Public iterator adapter

`WrappedIterator` lives in `src/text/text.zig` and is not a named export on
`zunic`. It converts engine spans and widths into public `Line` values.

Use `Text.wrap()` to construct the view. If a `Wrapped` is constructed by hand
with a zero width, its iterator clamps the width to one; `Text.wrap()` itself
continues to reject zero with `InvalidWidth`.
