# Reader codepoint iteration

[Reader view](README.md) · [Slice codepoint iteration](../text/codepoints/README.md)

`zunic.reader(input).codepoints()` incrementally decodes strict UTF-8 from a
caller-owned `std.Io.Reader` without allocating or adding another input buffer.
It yields the same `CodepointView` values as the strict slice iterator.

```zig
pub fn codepoints(self: Reader) ReaderCodepointIterator;

pub const ReaderCodepointIterator = struct {
    offset: u64,
    pub fn next(self: *ReaderCodepointIterator) ReaderCodepointError!?CodepointView;
};

pub const ReaderCodepointError = error{
    ReadFailed,
    InvalidUtf8,
    ReaderBufferTooSmall,
    OffsetOverflow,
};
```

`offset` counts bytes successfully decoded since the iterator was opened. A
successful call advances it after the complete scalar. Clean EOF returns
`null`; repeated calls remain `null`. An error is terminal and sticky: repeated
calls return the same error without reading or consuming more input.

Malformed, overlong, surrogate, out-of-range, and truncated encodings return
`InvalidUtf8` at the start of the offending sequence. `ReadFailed` preserves
the generic Reader diagnostic; inspect a concrete File Reader's stored error
for its underlying cause. `OffsetOverflow` occurs before consuming a scalar
whose ending offset cannot fit in `u64`.

Zunic uses `peek` and `toss`. An offending sequence is not tossed, although a
Reader refill may move buffered bytes and may read ahead in the underlying
source. Continue recovery through the same Reader rather than bypassing its
buffer: discard the failed iterator, diagnose and repair or skip input through
that Reader, then open a fresh iterator whose relative offset starts at zero.
Do not read from the raw file handle while buffered bytes remain. A split
encoding remains valid across refills.

The Reader's buffer needs capacity for the next UTF-8 prefix. One byte is
enough for ASCII; general UTF-8 needs at least four. Smaller multibyte capacity
returns `ReaderBufferTooSmall` before another read, and a zero-capacity Reader
returns it before any I/O. Arbitrary unbuffered Readers are unsupported.

## Blocking stdin example

```zig
const std = @import("std");
const zunic = @import("zunic");

pub fn main(init: std.process.Init) !void {
    var buffer: [4096]u8 = undefined;
    var stdin = std.Io.File.stdin().readerStreaming(init.io, &buffer);
    const source = zunic.reader(&stdin.interface);
    var points = source.codepoints();
    while (try points.next()) |point| {
        std.debug.print("U+{X}\n", .{point.value});
    }
}
```

`next()` may block until one complete scalar, clean EOF, a read failure, or a
provably invalid prefix is available. The iterator does not close stdin and
does not own the Reader or its buffer.
