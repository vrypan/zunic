# Terminal view — first draft

[Documentation index](../README.md) · [Implementation and next steps](implementation.md)

`zunic.terminal(bytes)` opens a borrowed view of UTF-8 containing terminal
escape sequences. This first version provides grapheme iteration only.
It does not yet track formatting, measure width, strip escapes, or wrap lines.

## Signatures

```zig
pub fn terminal(bytes: []const u8) Terminal;

// Terminal
pub fn graphemes(self: Terminal) TerminalGraphemes;

// TerminalGraphemes (Self below is its inferred iterator type)
pub fn iterator(self: TerminalGraphemes) Iterator;
pub fn next(self: *Self) error{EscapeInsideGrapheme}!?Span;
```

Opening the view does not scan or allocate. Each iterator starts at the
beginning and keeps its own position. Keep the borrowed bytes alive and
unchanged during iteration. `next()` returns `null` when no content remains;
empty input and input consisting only of recognized escapes produce no spans.

```zig
const bytes = "\x1b[31mcafe\u{0301}\x1b[0m";
var it = zunic.terminal(bytes).graphemes().iterator();
while (try it.next()) |span| {
    std.debug.print("{s}\n", .{bytes[span.start.value..span.end.value]});
}
// c, a, f, é — four graphemes
```

## What a span contains

Offsets index the original input, just like text-view spans. Each successful
span contains one complete grapheme and no recognized escapes. Surrounding
escapes are excluded. Formatting must change between complete graphemes.

If ignoring an escape would join the text on its two sides into one grapheme,
`next()` returns `error.EscapeInsideGrapheme`. It neither splits that grapheme
nor silently drops its internal formatting change:

```zig
const bytes = "e\x1b[31m\u{0301}";
var it = zunic.terminal(bytes).graphemes().iterator();
try std.testing.expectError(error.EscapeInsideGrapheme, it.next());
```

The error is reported before the affected grapheme is returned. For
`"ae\x1b[31m\u{0301}"`, the iterator returns `a`, then the error; it does not
return a standalone `e`. Later calls repeat the error. Earlier spans remain
valid. This checks full grapheme context, including flags and ZWJ emoji, not
just combining marks. Adjacent escapes are checked as a group. Leading and
trailing escapes are allowed.

Spans are not independently styled text and do not cover the skipped bytes.
The original input remains available as `Terminal.bytes`. Joining all successful
spans removes recognized escapes, but iteration can fail and malformed or
unsupported escapes remain ordinary content. A dedicated stripping operation
is still planned.

## Recognized escapes and malformed input

The scanner recognizes this limited subset:

- CSI: `ESC [` followed by parameter bytes (`0x30–0x3f`), intermediate bytes
  (`0x20–0x2f`), and one final byte (`0x40–0x7e`). This includes SGR styles
  and colors, as well as other CSI commands.
- OSC: `ESC ]` followed by a payload and terminated by BEL or `ESC \`.
  Payloads may contain UTF-8 bytes, but embedded C0 controls other than the
  terminator, DEL, or an unexpected ESC make recognition fail. This covers
  common titles and hyperlinks.

Recognition checks the sequence structure, not the meaning of its parameters.
SGR is the only formatting family planned for preservation and restoration.
Other recognized CSI/OSC commands are skipped without interpreting their effects;
there is no hyperlink or cursor state. All skipped sequences must lie between
graphemes; a sequence inside one causes `EscapeInsideGrapheme`. This is a
styled-text traversal, not a reconstruction of a terminal's screen. Tabs, newlines, and other content controls retain text-view behavior.

Incomplete, malformed, and unsupported escapes fall back to ordinary text.
A later complete escape can still be recognized. DCS, APC, other ESC commands,
and 8-bit C1 introducers are not supported in this draft. It is not a sanitizer.
Malformed UTF-8 outside recognized sequences follows the tolerant text iterator:
an invalid byte advances by one byte and is retained in the returned spans.
OSC payloads are skipped as bytes and are not UTF-8-validated.

## Standards used

Grapheme boundaries use Unicode 16.0.0
[UAX #29: Unicode Text Segmentation](https://www.unicode.org/reports/tr29/),
applied to each uninterrupted text segment. Boundary checks across escapes
reject input that would split a grapheme, including combining sequences, flags,
and ZWJ emoji. This rejection is a Zunic input restriction, not a UAX rule.

Escape recognition uses a subset of ECMA-48 control syntax and the OSC BEL
termination described in [XTerm Control Sequences](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html).
ANSI escape parsing is not a UAX operation, and this draft does not implement
the complete terminal control protocol.
