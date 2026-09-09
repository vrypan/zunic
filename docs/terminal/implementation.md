# Terminal view: implementation and next steps

[API and examples](README.md) · [Documentation index](../README.md)

## Current implementation

[terminal.zig](../../src/terminal/terminal.zig) holds the view and token iterator
in the internal `terminal` module. [escape.zig](../../src/terminal/escape.zig)
recognizes commands and [strip.zig](../../src/terminal/strip.zig) removes them.
The latter two files do not import Unicode engines or tables; stripping tests
compile independently of those modules. Shared span types live in
[types.zig](../../src/types.zig), so terminal code does not import the text view.
The public entry point remains `zunic.terminal(bytes)`.

It reads a complete borrowed slice, so it does not need to preserve a partially
received escape between input chunks. There is no streaming-input API yet.

The iterator locates uninterrupted content runs using an ESC byte search and
passes each run directly to the existing optimized grapheme iterator. It does
not add escape handling or errors to the plain-text engine's inner loop.

Before returning the final grapheme of a run, the token iterator saves its
boundary state by replaying it through the existing transition table. It returns
the content span immediately. Later calls return each following escape command.
Only when traversal reaches content again does it check that scalar against the
saved state. A join latches `EscapeInsideGrapheme`; earlier output is not retracted.
There is no lookahead across an escape to validate earlier output. The ordinary
grapheme engine still uses its normal lookahead within uninterrupted text.

Only graphemes directly before escapes are decoded again to save state. Other
graphemes use the engine's normal traversal. Keeping this extra pass local avoids
changing the plain-text engine to expose its temporary boundary state. The
iterator stores borrowed input, run offsets, the engine iterator, optional saved
boundary state, and an error flag. No formatting register or output buffer is
needed by token iteration. The terminal view has no separate grapheme API.

SGR classification accepts CSI with final `m`, numeric parameters and optional
semicolon/colon separators, and no private prefix or intermediate bytes. It does
not validate the meaning or range of individual SGR parameters. Other recognized
commands receive the `.other` tag. No commands are executed.

A failed escape scan leaves its bytes as content. Unexpected ESC bytes stop
recognition immediately, allowing a later introducer to be examined separately.
An unterminated payload may be read once during recognition and again as text;
repeated introducers do not repeatedly scan the entire remaining input. Work is
linear in the input size and storage does not grow with sequence length.

The plain-text engine is unchanged. This draft has correctness tests, including
the Unicode grapheme fixture with escapes inserted at each scalar boundary
in turn, accepting legal positions and rejecting positions inside graphemes;
performance cases and saved baseline results are described in [benchmarks](benchmarks.md).

## Byte-only stripping

`stripAnsi()` uses the same escape recognizer directly. It skips recognized
sequences and copies the remaining content into the caller's buffer. Short runs
use an unrolled prefix of up to 16 bytes, avoiding vector-search overhead between
dense commands. Longer runs use Zig's SIMD-capable `std.mem.findScalarPos()` to
locate the next ESC, then copy the intervening block. The search has a scalar
fallback on targets without vector support. Escape recognition is inlined at
its call sites; the recognized syntax is unchanged. The stripping path does not
call the token iterator, UTF-8 decoder, or grapheme engine, so it can remove an
escape inside a grapheme or even inside a UTF-8 encoding. A block copy is limited
to the remaining output capacity; on failure it leaves the same byte prefix as
the byte-at-a-time path. Forward copying permits the documented in-place use.
The output never grows; writing into storage starting
at the input address is safe because the write position never passes the read
position. Other overlapping storage is not supported.

Use `text()` on the result for Unicode operations. We do not duplicate width,
normalization, or wrapping on the terminal view.

## Possible later work — not implemented

Formatting-preserving wrapping would be a separate feature. Its input primitive
would be `tokens()`, with SGR state stored as active style properties rather than
an unbounded history of commands. Other recognized commands would be ignored.
An output line would need to combine borrowed content with generated reset and
restore sequences, so the current `Line` span would not be sufficient.

That design also needs a policy for partial output when a later token raises
`EscapeInsideGrapheme`. No formatting restoration, cursor emulation, or hyperlink
state is currently implemented.
