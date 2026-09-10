# Terminal view

[Documentation index](../README.md) · [Text view](../text/README.md) · [Shared conventions](../conventions.md)

`zunic.terminal(bytes)` opens a borrowed view of UTF-8 containing terminal
escape sequences. It provides token iteration and byte-only escape removal.
Use `zunic.text()` on stripped output for graphemes, width, normalization, and wrapping. The
terminal view does not provide those operations. Its token iterator tracks active
formatting in `it.state: zunic.TerminalState`.


## Signatures

```zig
pub fn terminal(bytes: []const u8) Terminal;
pub fn isAscii(self: Terminal) bool;
pub fn tokens(self: Terminal) TerminalTokens;
pub fn stripAnsi(self: Terminal, buffer: []u8) error{NoSpace}![]u8;
```

Opening the view does not scan or allocate. `Terminal.bytes` borrows the input.
Keep that storage alive and unchanged while iterating. This API is a first draft;
there is no terminal-aware width or wrapping operation yet.

`isAscii()` scans the raw bytes exactly as given -- no escape parsing, no
state tracking, no restriction to visible content. An all-ASCII escape
sequence counts as ASCII even if incomplete; a non-ASCII byte inside an OSC
payload fails the check even though `stripAnsi()` would remove it. It is a
byte-range test, not UTF-8 validation and not a check on what a terminal
would render. Scans the whole slice every call, with no cache. Over the same
raw bytes, it always agrees with `zunic.text(bytes).isAscii()`.

## Operations

| Page | Covers |
| --- | --- |
| [Tokens](tokens.md) | Grapheme and escape spans, command effects, errors during traversal |
| [Formatting state](state.md) | Active colors, attributes, links, and supported parameters |
| [Strip ANSI](strip-ansi.md) | Escape removal, buffer sizing, overlap, and partial writes |
| [Implementation](implementation.md) | Scanning decisions and limitations |
| [Benchmarks](benchmarks.md) | Native benchmarks and historical measurements |

## Use the output as plain text

```zig
const input = "\x1b[31mhello\x1b[0m";
var buffer: [input.len]u8 = undefined;
const plain = try zunic.terminal(input).stripAnsi(&buffer);
const text = zunic.text(plain);
try std.testing.expectEqual(@as(usize, 5), text.width());
```

`plain` borrows the output buffer. The Text view can also trim, segment, wrap,
or normalize those bytes. Stripping removes recognized escapes; it does not
interpret cursor movement or reconstruct a terminal screen.

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
SGR formatting and OSC 8 hyperlinks are tracked in [formatting state](state.md).
Other recognized CSI/OSC commands are exposed as `.other` tokens; there is no
cursor or screen state. `stripAnsi()` removes both kinds. In token iteration,
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

State interpretation also uses the [OSC 8 hyperlink proposal](https://gist.github.com/egmontkob/eb114294efbcd5adb1944c9f3cb5feda)
and [colored and styled underlines](https://sw.kovidgoyal.net/kitty/underlines/).
