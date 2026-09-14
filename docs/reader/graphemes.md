# Incremental Reader graphemes

[Reader view](README.md) · [Reader codepoints](codepoints.md) ·
[Text graphemes](../text/graphemes/README.md)

`zunic.reader(input).graphemes()` reports the current grapheme after every
strictly decoded codepoint. It uses the default Unicode 17 extended grapheme
rules without buffering the complete cluster or reading ahead to its boundary.

```zig
pub fn graphemes(self: Reader) ReaderGraphemeIterator;

pub const ReaderGraphemeSpan = struct { start: u64, end: u64 };

pub const ReaderGraphemeUpdate = struct {
    grapheme: ReaderGraphemeSpan,
    point: ?CodepointView,
    starts_new: bool,
    is_final: bool,
};

pub fn next(
    self: *ReaderGraphemeIterator,
) ReaderGraphemeError!?ReaderGraphemeUpdate;
```

The span is a cumulative snapshot of the current grapheme, relative to the
Reader position where the iterator was opened. `point` is the codepoint newly
consumed for this update. It is null only for the final clean-EOF update.
Result values contain no pointer into the Reader buffer.

`starts_new` means this point begins a new grapheme. It finalizes the preceding
snapshot and introduces the new snapshot in the same update. `is_final` means
clean EOF finalized the current grapheme. Most graphemes are therefore
completed by the next update's `starts_new`, while only the last grapheme gets
an `is_final` update.

For `e` + combining acute accent + `x`:

| Consumed | Span | point | `starts_new` | `is_final` |
| --- | --- | --- | --- | --- |
| `e` | `[0,1)` | U+0065 | true | false |
| U+0301 | `[0,3)` | U+0301 | false | false |
| `x` | `[3,4)` | U+0078 | true | false |
| EOF | `[3,4)` | null | false | true |

A nonempty stream containing N codepoints produces N scalar updates plus one
EOF update. Empty input with nonzero Reader capacity produces no update; as
with codepoint iteration, a zero-capacity Reader reports
`ReaderBufferTooSmall`. Do not append a codepoint for the EOF update, and do
not count only `is_final`: use `starts_new` to commit the preceding snapshot.

```zig
var input: std.Io.Reader = .fixed("e\u{0301}x");
var updates = zunic.reader(&input).graphemes();
var pending: ?zunic.ReaderGraphemeSpan = null;
var completed: usize = 0;
while (try updates.next()) |update| {
    if (update.starts_new and pending != null) completed += 1;
    pending = update.grapheme;
    if (update.is_final) {
        completed += 1;
        pending = null;
    }
}
```

Each active call consumes at most one codepoint and may block only while the
strict decoder obtains that codepoint. An open pipe can keep the current
grapheme provisional indefinitely, but each arriving codepoint still produces
an update immediately. Reader prefetch may occur; Zunic does not consume a
following scalar to decide the current result.

## Why incremental updates?

Unicode places no upper bound on the number of codepoints in one grapheme. For
example, a base character can be followed by an arbitrary number of combining
marks, all belonging to the same grapheme. Each Unicode codepoint takes from
one to four bytes in UTF-8, so the byte length of a grapheme is also unbounded.

Zunic therefore cannot return a complete grapheme from a blocking Reader while
remaining allocation-free and using bounded internal storage. It would have to
buffer the entire grapheme, impose an arbitrary maximum, or make the caller
supply a potentially large buffer.

Instead, the iterator returns the current grapheme representation after each
codepoint. The consumer can display or accumulate that representation as data
arrives. `starts_new` confirms the preceding grapheme when the next boundary is
known, and `is_final` confirms the last grapheme at clean EOF. The iterator
itself remains constant in size regardless of grapheme length.

The iterator does not retain the grapheme's bytes or calculate terminal width.
Consumers that need the text can encode each non-null `point`, as in the
example below, or retain input themselves.

The errors and buffer requirements are identical to Reader codepoint
iteration. Errors are sticky and never synthesize a final update. On failure,
the last snapshot remains provisional; discard the iterator before recovering
through the same buffered Reader. The caller owns the Reader and buffer, and
copies share the same underlying cursor.

## Blocking stdin example

```zig
const std = @import("std");
const zunic = @import("zunic");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    var stdin_buffer: [4096]u8 = undefined;
    var stdin = std.Io.File.stdin().readerStreaming(init.io, &stdin_buffer);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    defer stdout.interface.flush() catch {};

    var current: std.ArrayList(u8) = .empty;
    defer current.deinit(allocator);

    var graphemes = zunic.reader(&stdin.interface).graphemes();

    while (try graphemes.next()) |update| {
        // The new point belongs to the next grapheme, so finish the preceding
        // buffer before appending it.
        if (update.starts_new and current.items.len != 0) {
            try stdout.interface.writeAll(current.items);
            try stdout.interface.writeByte('\n');
            current.clearRetainingCapacity();
        }

        if (update.point) |point| {
            var encoded: [4]u8 = undefined;
            const len = try std.unicode.utf8Encode(point.value, &encoded);
            try current.appendSlice(allocator, encoded[0..len]);
        }

        // The EOF update has no point, so this does not append the final
        // codepoint twice.
        if (update.is_final) {
            try stdout.interface.writeAll(current.items);
            try stdout.interface.writeByte('\n');
            current.clearRetainingCapacity();
        }
    }

    try stdout.interface.flush();
}
```

For input containing `e` + combining acute accent + `x`, this prints:

```text
é
x
```

The `ArrayList` is consumer-owned storage for the text being printed; Zunic's
iterator remains allocation-free. A program with its own grapheme-length limit
can use a fixed buffer here and define the appropriate overflow behavior.
