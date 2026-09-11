# Terminal tokens

[Terminal view](README.md) · [Formatting state](state.md) · [Strip ANSI](strip-ansi.md)

## Signatures

```zig
pub fn tokens(self: Terminal) TerminalTokens;

pub const StyleFields = packed struct {
    foreground: bool = false,
    background: bool = false,
    underline_color: bool = false,
    bold: bool = false,
    faint: bool = false,
    italic: bool = false,
    fraktur: bool = false,
    inverse: bool = false,
    concealed: bool = false,
    strikethrough: bool = false,
    overline: bool = false,
    proportional: bool = false,
    underline: bool = false,
    blink: bool = false,
    frame: bool = false,
    font: bool = false,
    script: bool = false,
    ideogram: bool = false,
    unhandled: bool = false,
};

pub const Escape = struct {
    span: Span,
    effect: union(enum) { sgr: StyleFields, hyperlink, other },
};
pub const TerminalToken = union(enum) {
    grapheme: Span,
    escape: Escape,
};

// TerminalTokens (Self below is its inferred iterator type)
pub fn iterator(self: TerminalTokens) TokenIterator;
pub fn next(self: *Self) error{EscapeInsideGrapheme}!?TerminalToken;
// Iterator field: state: TerminalState = .{};
```

Opening the view does not scan or allocate. Each token iterator starts at the
beginning and keeps its own position. Keep its input alive and unchanged during
iteration. Empty input produces no tokens; input consisting only of recognized
escapes produces escape tokens. Repeated calls at the end return `null`.

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
        .escape => |esc| std.debug.print("escape: {t}\n", .{std.meta.activeTag(esc.effect)}),
    }
}
// escape: sgr, text: h, text: i, escape: sgr
```

Escape effects are `.sgr` with affected fields, `.hyperlink` for valid OSC 8
link commands, and `.other` for remaining recognized CSI/OSC commands. Before returning a command, the iterator updates `it.state` for
supported SGR parameters and OSC 8 links. Other commands leave state unchanged.
Callers can copy all tokens, keep SGR only, or omit escape tokens.
To work with plain text, call `stripAnsi()` and open a text view on the result.

Offsets index the original input. Content spans exclude recognized escapes and
are not independently styled text. The complete input remains available as
`Terminal.bytes`. On accepted input, each content span is a complete grapheme.
Malformed or unsupported escapes remain ordinary content.

## Escape effects

An escape keeps its original `span` and reports its `effect`:

- `.sgr`: a `StyleFields` bitset listing fields assigned by this command.
- `.hyperlink`: a valid OSC 8 opening or closing command. Read `it.state.link`.
- `.other`: another recognized command, including an OSC 8 command with a
  missing parameter/URI separator. It leaves state unchanged.

Read the resulting values from `it.state`; they have already been updated.
Several flags can be set by one command. Flags report assignments, even if the
value was already the same. A full SGR reset marks all style fields, but leaves
links alone. Flags accumulate across the entire command, including assignments
that later parameters overwrite. They start empty for each new SGR token.

```zig
var it = zunic.terminal("\x1b[1;31;999m").tokens().iterator();
const esc = (try it.next()).?.escape;
switch (esc.effect) {
    .sgr => |fields| {
        try std.testing.expect(fields.bold and fields.foreground);
        try std.testing.expect(it.state.bold);
        try std.testing.expectEqual(@as(u8, 1), it.state.foreground.indexed);
        try std.testing.expect(fields.unhandled); // 999 is unsupported.
    },
    .hyperlink, .other => unreachable,
}
```

`unhandled` means at least one SGR parameter was unsupported, invalid, overflowing,
or incomplete. Successfully processed fields are still reported. A rejected
color does not mark its field unless another parameter assigned that field.
A later reset does not clear `unhandled` for that command. Inspect the original
span when you need the unhandled bytes. This adds no new iterator error.

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
an opening style. There is no automatic rollback or closing reset. Formatting state retains the
effects of commands already returned, including after repeated errors.

Later calls repeat the error. Iterator copies retain the same saved boundary
state. The check handles flags, ZWJ emoji, and other full grapheme context, not
just combining marks. Each adjacent escape is returned separately; the boundary
check waits until content is encountered. Leading and trailing escapes are allowed.

## Standards used

Grapheme boundaries use Unicode 17.0.0 UAX #29. Rejecting escapes inside a
grapheme is a Zunic restriction. Escape recognition and effects use the
[terminal standards and subset](README.md#standards-used).
