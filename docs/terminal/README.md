# Terminal view — first draft

[Documentation index](../README.md) · [Implementation and next steps](implementation.md)

`zunic.terminal(bytes)` opens a borrowed view of UTF-8 containing terminal
escape sequences. It provides token iteration and byte-only escape removal.
Use `zunic.text()` on stripped output for graphemes, width, normalization, and wrapping. The
terminal view does not provide those operations or track formatting state.

## Signatures

```zig
pub fn terminal(bytes: []const u8) Terminal;

// Terminal
pub fn tokens(self: Terminal) TerminalTokens;
pub fn stripAnsi(self: Terminal, buffer: []u8) error{NoSpace}![]u8;

pub const Escape = struct {
    span: Span,
    kind: enum { sgr, other },
};
pub const TerminalToken = union(enum) {
    grapheme: Span,
    escape: Escape,
};

// TerminalTokens (Self below is its inferred iterator type)
pub fn iterator(self: TerminalTokens) TokenIterator;
pub fn next(self: *Self) error{EscapeInsideGrapheme}!?TerminalToken;
```

Opening the view does not scan or allocate. Each token iterator starts at the
beginning and keeps its own position. Keep its input alive and unchanged during
iteration. Empty input produces no tokens; input consisting only of recognized
escapes produces escape tokens. Repeated calls at the end return `null`.

## Strip escapes into a buffer

`stripAnsi(buffer)` removes recognized CSI/OSC sequences and copies every other
byte unchanged. It allocates nothing, does not decode or validate UTF-8, and
performs no grapheme checks. `e + SGR + accent` becomes `e + accent`, without
raising `EscapeInsideGrapheme`. It also accepts malformed UTF-8, including escapes
between bytes of a multi-byte encoding. It makes no promise of valid UTF-8 output.
Ordinary tabs, newlines, NULs, and other non-escape bytes are retained.

```zig
const input = "\x1b[31mcafe\x1b[0m\u{0301}";
var buffer: [input.len]u8 = undefined;
const plain = try zunic.terminal(input).stripAnsi(&buffer);
try std.testing.expectEqualStrings("cafe\u{0301}", plain);
try std.testing.expectEqual(@as(usize, 4), zunic.text(plain).width());
var graphemes = zunic.text(plain).graphemes().iterator();
var count: usize = 0;
while (graphemes.next() != null) count += 1;
try std.testing.expectEqual(@as(usize, 4), count);
```

The result is the written prefix of `buffer` as `[]u8`, with no NUL terminator.
Output cannot exceed `input.len`; a buffer that large always suffices. Exact
output capacity is also enough. Empty or escape-only input needs no capacity.

The only error is `NoSpace`. Bytes copied before the error remain written,
possibly ending inside a UTF-8 encoding: capacity is checked per byte. To retry,
use the original input with a larger buffer. Use separate storage or a buffer
starting at the same address as the input for in-place compaction. Other overlap
is unsupported. In-place writes alter the original input, including on failure.

Malformed and unsupported escapes are retained, following the recognition
policy below. The name does not promise removal of every terminal protocol.

## Tokens

`tokens()` returns content and recognized escape commands in their original
order, including leading and trailing commands. On input accepted through the
end, token spans cover every byte exactly once. Both variants borrow their
bytes from the original input:

```zig
const bytes = "\x1b[31mhi\x1b[0m";
var it = zunic.terminal(bytes).tokens().iterator();
while (try it.next()) |token| {
    switch (token) {
        .grapheme => |span| std.debug.print("text: {s}\n", .{bytes[span.start.value..span.end.value]}),
        .escape => |esc| std.debug.print("escape: {t}\n", .{esc.kind}),
    }
}
// escape: sgr, text: h, text: i, escape: sgr
```

SGR sequences are tagged `.sgr`; other recognized CSI/OSC commands are tagged
`.other`. The iterator identifies commands but does not execute them or track
their effects. Callers can copy all tokens, keep SGR only, or omit escape tokens.
To work with plain text, call `stripAnsi()` and open a text view on the result.

Offsets index the original input. Content spans exclude recognized escapes and
are not independently styled text. The complete input remains available as
`Terminal.bytes`. On accepted input, each content span is a complete grapheme.
Malformed or unsupported escapes remain ordinary content.

## Errors are reported when encountered

Formatting must change between complete graphemes. The iterator does not check
content beyond an escape before returning earlier tokens. It saves the preceding
grapheme state and checks the first content scalar when traversal reaches it.
If that scalar joins the earlier grapheme, it returns `EscapeInsideGrapheme`:

```zig
const bytes = "e\x1b[31m\u{0301}";
var it = zunic.terminal(bytes).tokens().iterator();
_ = (try it.next()).?.grapheme; // e
_ = (try it.next()).?.escape;   // SGR
try std.testing.expectError(error.EscapeInsideGrapheme, it.next());
```

Nothing is retracted: earlier spans still index the same bytes, but the last
content span can be only a prefix of the grapheme whose continuation caused the error.
Consumers that already wrote tokens may have produced partial output, including
an opening style. There is no automatic rollback or closing reset.

Later calls repeat the error. Iterator copies retain the same saved boundary
state. The check handles flags, ZWJ emoji, and other full grapheme context, not
just combining marks. Each adjacent escape is returned separately; the boundary
check waits until content is encountered. Leading and trailing escapes are allowed.

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
Other recognized CSI/OSC commands are exposed as `.other` tokens; there is no
hyperlink or cursor state. `stripAnsi()` removes both kinds. In token iteration,
recognized escapes must lie between graphemes; a sequence inside one causes
`EscapeInsideGrapheme`. This is a
styled-text traversal, not a reconstruction of a terminal's screen. Tabs, newlines,
and other content controls retain text-view behavior.

Incomplete, malformed, and unsupported escapes fall back to ordinary text.
A later complete escape can still be recognized. DCS, APC, other ESC commands,
and 8-bit C1 introducers are not supported in this draft. It is not a sanitizer.
Malformed UTF-8 outside recognized sequences follows the tolerant text iterator:
an invalid byte advances by one byte and is retained in the returned spans.
OSC payloads are recognized as bytes and are not UTF-8-validated.

## Standards used

Token grapheme boundaries use Unicode 16.0.0
[UAX #29: Unicode Text Segmentation](https://www.unicode.org/reports/tr29/),
applied to each uninterrupted text segment. Boundary checks across escapes
reject input that would split a grapheme, including combining sequences, flags,
and ZWJ emoji. This rejection is a Zunic input restriction, not a UAX rule.

Escape recognition uses a subset of ECMA-48 control syntax and the OSC BEL
termination described in [XTerm Control Sequences](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html).
ANSI escape parsing is not a UAX operation, and this draft does not implement
the complete terminal control protocol.

`stripAnsi()` uses only the escape syntax above. It uses no Unicode properties
or UAX algorithm; its byte-removal behavior is independent of Unicode versions.
