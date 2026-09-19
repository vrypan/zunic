# Incremental Reader graphemes

[Reader view](README.md) · [Reader codepoints](codepoints.md) ·
[Text graphemes](../text/graphemes/README.md)

`zunic.reader(input).graphemes()` yields newly consumed UTF-8 bytes and boundary
flags after every strictly decoded codepoint. It uses the default Unicode 17
extended grapheme rules without buffering the complete cluster or reading ahead
to its boundary.

```zig
pub fn graphemes(self: Reader) ReaderGraphemeIterator;

pub const ReaderGraphemeUpdate = struct {
    starts_new: bool,
    is_final: bool,
    // Owns up to four UTF-8 bytes internally.
    pub fn bytes(self: *const ReaderGraphemeUpdate) []const u8;
};

pub fn next(
    self: *ReaderGraphemeIterator,
) ReaderGraphemeError!?ReaderGraphemeUpdate;
```

`update.bytes()` returns the original UTF-8 bytes newly consumed for this
update: one complete codepoint,
one to four bytes. It returns an empty slice for the final clean-EOF update.
These are the added bytes, not the entire grapheme. Updates contain no spans
or source offsets.

Each update owns its bytes; result values contain no pointer into the Reader
buffer. Retaining or copying an update preserves its bytes across subsequent
reads and buffer reuse. The slice returned by `bytes()` borrows that particular
update, so it is valid only while the update remains alive and unchanged.
Keep the update in a local variable before taking its byte slice.

`starts_new` means these bytes begin a new grapheme. It finalizes the preceding
grapheme and introduces the new grapheme in the same update. `is_final` means
clean EOF finalized the current grapheme. Most graphemes are therefore
completed by the next update's `starts_new`, while only the last grapheme gets
an `is_final` update.

For `e` + combining acute accent + `x`:

| Consumed | `bytes()` (hex) | `starts_new` | `is_final` |
| --- | --- | --- | --- |
| `e` | `65` | true | false |
| U+0301 | `CC 81` | false | false |
| `x` | `78` | true | false |
| EOF | empty | false | true |

A nonempty stream containing N codepoints produces N scalar updates plus one
EOF update. Empty input with nonzero Reader capacity produces no update; as
with codepoint iteration, a zero-capacity Reader reports
`ReaderBufferTooSmall`. Appending `update.bytes()` at EOF adds nothing. Do not
count only `is_final`: use `starts_new` to commit the preceding grapheme.

```zig
var input: std.Io.Reader = .fixed("e\u{0301}x");
var updates = zunic.reader(&input).graphemes();
var pending = false;
var completed: usize = 0;
while (try updates.next()) |update| {
    if (update.starts_new and pending) completed += 1;
    pending = true;
    if (update.is_final) {
        completed += 1;
        pending = false;
    }
}
```

Each active call consumes at most one codepoint and may block only while the
strict decoder obtains that codepoint. An open pipe can keep the current
grapheme provisional indefinitely, but each arriving codepoint still produces
an update immediately. Reader prefetch may occur; Zunic does not consume a
following scalar to decide the current result.

## Incremental measurements

Select `.measured()` when opening the iterator to include the current
grapheme's terminal width and renderability:

```zig
var input: std.Io.Reader = .fixed("e\u{0301}界");
var updates = zunic.reader(&input).graphemes().measured();
while (try updates.next()) |update| {
    std.debug.print("added={s} columns={d} renderable={} final={}\n", .{
        update.bytes(), update.columns, update.renderable, update.is_final,
    });
}
```

The measured iterator returns `ReaderMeasuredGraphemeUpdate`, with the same
owned `bytes()`, `starts_new`, and `is_final` behavior, plus:

```zig
columns: u2,
renderable: bool,
```

These fields describe the **entire current grapheme after adding the returned
bytes**, using the same [width policy](../text/width/README.md) as
`text(bytes).graphemes().measured()`. They do not describe just the added
codepoint and are not deltas to add to a running width.

| Update | `bytes()` | `starts_new` | `columns` | `renderable` | `is_final` |
| --- | --- | --- | --- | --- | --- |
| `e` | `e` | true | 1 | true | false |
| Accent | `CC 81` | false | 1 | true | false |
| `界` | `E7 95 8C` | true | 2 | true | false |
| EOF | empty | false | 2 | true | true |

A new-grapheme update reports the new grapheme's measurement. Retain the
preceding update's measurement if you need it when that preceding grapheme
is finalized. The EOF update repeats the last measurement without adding
bytes. Empty input produces no measurement, and errors never finalize one.

The current width or renderability can change in either direction as the
grapheme grows. A renderer can display provisional text immediately, then
remeasure its placement and redraw when an update changes these fields.
`renderable = false` follows Zunic's existing display policy; it does not
remove or replace any returned bytes.

Call `.measured()` on a fresh iterator, before calling `next()`, and then use
only the returned `ReaderMeasuredGraphemeIterator`. Enabling measurement after
an unmeasured iterator has yielded a codepoint or reached EOF panics: its
earlier grapheme bytes and widths cannot be reconstructed from boundary state.
Copies still share the underlying Reader cursor.

Measurement uses constant storage, performs no lookahead, and does not retain
the complete grapheme. A selector can revise its preceding base: `⌚` reports
two columns, and an immediately following VS15 changes the current cluster to
one. The width counter remains bounded while preserving this behavior.
Omitting `.measured()` excludes this state and measurement work.

## Why incremental updates?

Unicode places no upper bound on the number of codepoints in one grapheme. For
example, a base character can be followed by an arbitrary number of combining
marks, all belonging to the same grapheme. Each Unicode codepoint takes from
one to four bytes in UTF-8, so the byte length of a grapheme is also unbounded.

Zunic therefore cannot return a complete grapheme from a blocking Reader while
remaining allocation-free and using bounded internal storage. It would have to
buffer the entire grapheme, impose an arbitrary maximum, or make the caller
supply a potentially large buffer.

Instead, the iterator returns the added bytes and boundary flags after each
codepoint. The consumer can display or accumulate those bytes as data
arrives. `starts_new` confirms the preceding grapheme when the next boundary is
known, and `is_final` confirms the last grapheme at clean EOF. The iterator
itself remains constant in size regardless of grapheme length.

The iterator does not retain the complete grapheme or calculate terminal
width. Consumers that need the text can append `update.bytes()` to their own
buffer, as in the example below. No UTF-8 re-encoding is needed. Zunic still
decodes the codepoint internally to determine grapheme boundaries; consumers
that need decoded codepoint properties can use `reader(input).codepoints()`.

The errors and buffer requirements are identical to Reader codepoint
iteration. Errors are sticky and never synthesize a final update. On failure,
the last grapheme remains provisional; discard the iterator before recovering
through the same buffered Reader. The caller owns the Reader and buffer, and
copies share the same underlying cursor.

## Tracking source positions

Consumers needing source positions can keep a byte counter and the current
grapheme's start. At `starts_new`, the preceding grapheme covers
`[start, offset)`; then set `start = offset`. Add `update.bytes().len` to
`offset` for every update. At `is_final`, `[start, offset)` identifies the last
grapheme. Start both counters at zero for positions relative to the Reader
cursor where iteration began.

These positions refer to the original stream, not the Reader's reusable buffer.
Only use them to slice input you have retained separately.

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
        // The new bytes belong to the next grapheme, so finish the preceding
        // buffer before appending it.
        if (update.starts_new and current.items.len != 0) {
            try stdout.interface.writeAll(current.items);
            try stdout.interface.writeByte('\n');
            try stdout.interface.flush();
            current.clearRetainingCapacity();
        }

        try current.appendSlice(allocator, update.bytes());

        // The EOF update adds no bytes and finalizes the last grapheme.
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
