# Codepoint iteration implementation

[API](README.md) · [Source](../../../src/text/text.zig)

`Codepoints` holds a borrowed byte slice. `iterator()` initializes a
`CodepointIterator` with the same slice, offset zero, and no error.

```zig
bytes: []const u8,
offset: usize = 0,
err: ?DecodeError = null,
```

`next()` first checks for a previously recorded error or exhaustion. Otherwise,
it calls `encoding.utf8.step()` on the remaining slice. A valid result
advances the offset by the sequence length and constructs a
`cp.CodepointView` from the decoded value. A decoding failure records
`.invalid_utf8` and returns null without advancing.

The decoder rejects surrogate encodings, values above Unicode's maximum,
overlong encodings, broken continuation bytes, and truncated sequences.
A literal U+FFFD encoded correctly is returned as an ordinary value; the
iterator never uses it as an error sentinel.

No Unicode property lookup is needed for this traversal. The iterator uses
the UTF-8 decoder directly, rather than `encoding.decoded_token`, whose
additional facts serve segmentation and layout. The public `next()` method
returns an optional view; decoding errors are retained in the iterator.

The offset and error state are ordinary value fields, so copying the iterator
provides a checkpoint without allocation. The returned codepoint view also
owns its value and retains no reference to the input bytes.

Run `zig build test-text` for malformed-input, exhaustion, and checkpoint
checks, and `zig build test-api` for public type and property integration.
