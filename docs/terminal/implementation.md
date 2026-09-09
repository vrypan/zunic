# Terminal view: implementation and next steps

[API and examples](README.md) · [Documentation index](../README.md)

## Current implementation

[terminal.zig](../../src/terminal/terminal.zig) holds the view and token iterator
in the internal `terminal` module. [escape.zig](../../src/terminal/escape.zig)
recognizes commands, [state.zig](../../src/terminal/state.zig) tracks formatting,
and [strip.zig](../../src/terminal/strip.zig) removes them.
These three files do not import Unicode engines or tables; stripping tests
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
boundary state, an error flag, and a formatting state struct. No output buffer is
needed by token iteration. The terminal view has no separate grapheme API.

SGR classification accepts CSI with final `m`, numeric parameters and optional
semicolon/colon separators, and no private prefix or intermediate bytes. This
classification checks syntax only; interpretation then checks supported values.
Valid OSC 8 commands receive the `.hyperlink` effect; other recognized commands
receive `.other`. The iterator applies supported SGR parameters
and OSC 8 link commands before returning their tokens. During the same pass,
SGR assignments set flags in a packed `StyleFields` value. No second parse or
old/new state comparison is needed. SGR 0 marks all style fields; `unhandled`
accumulates independently and survives resets within that command. Invalid and
unsupported parameters set `unhandled` without inventing effects for skipped
parameters. The original span is always available for exact command bytes.
The iterator does not execute cursor or screen commands. [Formatting state](state.md) lists the supported parameters.

State records active properties, not a history of commands. Colors retain their
palette index or RGB value; they are not resolved against a particular terminal's
palette. Link parameters and URIs borrow input slices, allowing arbitrary lengths
without allocating or copying strings. A state copy borrows the same input.
SGR 0 resets every formatting field while preserving the link. Link closing is a
separate OSC 8 operation.

The struct includes less common SGR fields now, so future formatting and wrapping
work can use the same layout. It has no fixed ABI or guarantee of covering future
vendor extensions. Cursor positions, screen contents, terminal modes, palette
changes, and command stacks are outside this styled-text view.

Parameter parsing uses constant storage and checks numeric overflow. Colon groups
stay together, so an unsupported underline or color subparameter cannot become a
separate attribute. Invalid RGB components consume their complete known group but
leave the color unchanged. An unknown semicolon color mode stops processing that
SGR because its length is unknown. Earlier parameters are retained; later commands
still work. This is our explicit recovery policy, not a promise to match every
terminal's handling of malformed commands.

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
would be `tokens()`, using the active formatting and link state already stored
on its iterator. Other recognized commands would be ignored.
An output line would need to combine borrowed content with generated reset and
restore sequences, so the current `Line` span would not be sufficient.

That design also needs a policy for partial output when a later token raises
`EscapeInsideGrapheme`. No formatting restoration or cursor emulation is currently implemented.
