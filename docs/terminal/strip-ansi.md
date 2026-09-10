# Remove ANSI escapes

[Terminal view](README.md) · [Tokens](tokens.md) · [Implementation](implementation.md)

```zig
pub fn stripAnsi(self: Terminal, buffer: []u8) error{NoSpace}![]u8;
```

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
[recognition policy](README.md#recognized-escapes-and-malformed-input). The name does not promise removal of every terminal protocol.

## Standards used

This method uses the [escape syntax](README.md#standards-used) described for the
Terminal view. It uses no Unicode properties or UAX algorithm; stripping is
independent of Unicode versions.
