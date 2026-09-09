# Terminal view: implementation and next steps

[API and examples](README.md) · [Documentation index](../README.md)

## Current implementation

[terminal.zig](../../src/terminal.zig) holds the view and a small escape scanner.
It reads a complete borrowed slice, so it does not need to preserve a partially
received escape between input chunks. There is no streaming-input API yet.

The iterator locates uninterrupted content runs using an ESC byte search and
passes each run directly to the existing optimized grapheme iterator. It does
not add escape handling or errors to the plain-text engine's inner loop.

Before returning the final grapheme of a run, it skips the following escapes
and examines the first content scalar after them. It reconstructs the final
grapheme's state using the existing transition table. If the next scalar joins
that grapheme, it latches `EscapeInsideGrapheme` and returns the error instead of
a partial grapheme. Otherwise it returns the span and continues with the next
run. No reconstructed state is needed at the end of input.

Only graphemes directly before escapes are decoded again for this check. Other
graphemes use the engine's normal traversal. Keeping this extra pass local avoids
changing the plain-text engine to expose its temporary boundary state. The
iterator stores borrowed input, run offsets, the engine iterator, and an error
flag. No formatting register or output buffer is needed yet.

A failed escape scan leaves its bytes as content. Unexpected ESC bytes stop
recognition immediately, allowing a later introducer to be examined separately.
An unterminated payload may be read once during recognition and again as text;
repeated introducers do not repeatedly scan the entire remaining input. Work is
linear in the input size and storage does not grow with sequence length.

The plain-text engine is unchanged. This draft has correctness tests, including
the Unicode grapheme fixture with escapes inserted at each scalar boundary
in turn, accepting legal positions and rejecting positions inside graphemes;
terminal-specific performance has not yet been benchmarked.

## Proposed next steps — not implemented

1. Add a plain-text chunk iterator, exposed as `terminal.stripAnsi()`, with
   `writeTo(buffer)` for collecting its output. Keep this separate from Unicode
   normalization. Decide whether its escape coverage should be broader first.
2. Add measured graphemes and width using content scalars only. Keep the existing
   width policy and state clearly that cursor movement is not simulated.
3. Track supported SGR properties in a formatting-state struct: style flags,
   underline mode, and tagged foreground/background colors. Preserve SGR only;
   skip other recognized commands without executing them. Hyperlink state is
   out of scope. Decide exact supported SGR attributes before promising restoration.
4. Add wrapping with an output type that can combine borrowed content and
   generated formatting. Each independently printable line should restore the
   active style, emit its content, and close active SGR formatting.
   The next line restores the state saved at the break.

Formatting state and grapheme boundary state have different jobs. Keep them
separate; a formatting change inside a grapheme is rejected. The future
formatting state should describe active properties rather than accumulate an
unbounded history of escape commands.

A terminal line cannot always be represented by the existing `Line` span:
closing and restoring styles requires bytes absent from the original input.
Settle that output contract before implementing wrapping. In particular, retain
SGR escapes between graphemes and at the start and end of input; the grapheme spans
alone intentionally do not contain all of them.
