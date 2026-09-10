# Formatting state

[Terminal API](README.md) · [Implementation](implementation.md)

`it.state` records the formatting active after the last returned token. A new
iterator starts with `TerminalState{}`. The state is a value: save or copy it with
ordinary assignment. It allocates nothing. Link slices borrow the iterator input
and remain valid only while that input stays alive and unchanged.

This layout covers text formatting and hyperlinks, including the less common
fields listed below. It does not represent a terminal screen, cursor, palette
contents, title, keyboard modes, or a stack of saved states. Future protocol
extensions may still require changes; the layout is not a fixed ABI.

## Traversal example

Each iterator starts with default colors, no attributes, and no link. State is
updated before an escape token is returned. For a grapheme token it describes
that grapheme's formatting. Copying an iterator copies its state.

```zig
const bytes = "\x1b[1;31mA\x1b[0m";
var it = zunic.terminal(bytes).tokens().iterator();
_ = (try it.next()).?.escape;
try std.testing.expect(it.state.bold);
try std.testing.expectEqual(@as(u8, 1), it.state.foreground.indexed);
_ = (try it.next()).?.grapheme; // A is bold, with palette color 1.
_ = (try it.next()).?.escape;
try std.testing.expectEqualDeep(zunic.TerminalState{}, it.state);
```

SGR resets affect formatting, but do not close OSC 8 links. Link URI and parameter
slices borrow the original input, including in saved copies of state. Keep that
input alive. The layout and supported parameters are listed below.

## Layout

```zig
pub const TerminalState = struct {
    foreground: Color = .default,
    background: Color = .default,
    underline_color: Color = .default,
    bold: bool = false,
    faint: bool = false,
    italic: bool = false,
    fraktur: bool = false,
    inverse: bool = false,
    concealed: bool = false,
    strikethrough: bool = false,
    overline: bool = false,
    proportional: bool = false,
    underline: Underline = .none,
    blink: Blink = .none,
    frame: Frame = .none,
    font: Font = .default,
    script: Script = .normal,
    ideogram: Ideogram = .{},
    /// OSC 8 data borrows the iterator input. SGR resets do not close links.
    link: ?Link = null,

    pub const Color = union(enum) {
        default,
        indexed: u8,
        rgb: struct { r: u8, g: u8, b: u8 },
    };
    pub const Underline = enum { none, single, double, curly, dotted, dashed };
    pub const Blink = enum { none, slow, rapid };
    pub const Frame = enum { none, framed, encircled };
    pub const Font = enum { default, alternate_1, alternate_2, alternate_3, alternate_4, alternate_5, alternate_6, alternate_7, alternate_8, alternate_9 };
    pub const Script = enum { normal, superscript, subscript };
    pub const Ideogram = struct {
        underline: bool = false,
        double_underline: bool = false,
        overline: bool = false,
        double_overline: bool = false,
        stress: bool = false,
    };
    pub const Link = struct {
        /// Full parameter string, including id= and any unknown parameters.
        params: []const u8,
        uri: []const u8,
    };
};

```

`Color.default` preserves the request to use the terminal default; it does not
mean a particular RGB value. `indexed` keeps a palette index (0–255), including
basic and bright colors. Bold and faint are independent. Inverse does not swap
the stored colors. Default underline color follows the terminal's foreground
policy; the stored value remains `.default`.

A link stores the full parameter string, including `id=` and unknown parameters,
and the complete URI. Opening another link replaces it. An empty URI closes it.
An SGR reset leaves the link open. No URI validation or link activation occurs.

## Parameters tracked during traversal

| Parameters | Fields affected |
| --- | --- |
| SGR 0 or an empty parameter | Reset all fields except `link` |
| 1, 2; reset 22 | Bold, faint |
| 3, 20; reset 23 | Italic, Fraktur |
| 4, 21, 4:0 through 4:5; reset 24 | Underline style |
| 5, 6; reset 25 | Slow or rapid blink |
| 7, 8, 9; resets 27, 28, 29 | Inverse, concealed, strikethrough |
| 10 through 19 | Default or alternate font |
| 26; reset 50 | Proportional spacing |
| 30–37, 90–97, 38; reset 39 | Foreground color |
| 40–47, 100–107, 48; reset 49 | Background color |
| 51, 52; reset 54 | Framed or encircled |
| 53; reset 55 | Overline |
| 58; reset 59 | Underline color |
| 60 through 64; reset 65 | Ideogram marks |
| 73, 74; reset 75 | Superscript or subscript |
| OSC 8 | Link parameters and URI; effect is `.hyperlink` |

Extended colors accept `38;5;n` and `38;2;r;g;b`, with `48` and `58` selecting
background and underline color. Colon forms accept `38:5:n`, `38:2:r:g:b`,
`38:2::r:g:b`, and `38:2:0:r:g:b`. Components and indices must be 0–255.
Nonzero color-space identifiers and additional color fields are unsupported.
The state describes the requested formatting; individual terminals may display
some attributes differently or ignore them.

Parameters apply in order. Unknown numeric parameters and unsupported colon
groups are ignored. Invalid colors leave the previous color unchanged. A known
semicolon color mode consumes all its components even if one is invalid. A bad
or unknown semicolon color mode stops that SGR; otherwise its remaining values
could accidentally become attributes. Numeric overflow is ignored, never wrapped.

Other recognized commands do not change state. Malformed escape sequences remain
ordinary content under the token scanner's existing rules. SGR effects report affected fields and an `unhandled` flag; see
[escape effects](tokens.md#escape-effects). Unknown effects are
not stored, so state cannot reproduce arbitrary escape sequences losslessly.
Use the original escape tokens when exact command preservation is required.

Graphemes, end-of-input, and `EscapeInsideGrapheme` leave formatting unchanged.
Commands returned before an error remain applied; there is no rollback or
implicit closing reset. `stripAnsi()` does not use or update formatting state.

## References

State interpretation uses [ECMA-48](https://ecma-international.org/publications-and-standards/standards/ecma-48/),
[XTerm Control Sequences](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html),
[colored and styled underlines](https://sw.kovidgoyal.net/kitty/underlines/), and
the [OSC 8 hyperlink proposal](https://gist.github.com/egmontkob/eb114294efbcd5adb1944c9f3cb5feda).
It uses no Unicode properties or UAX algorithms. Token grapheme boundaries still
use UAX #29 as described in the [terminal API](README.md).
