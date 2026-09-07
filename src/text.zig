//! Public, question-shaped views over a borrowed UTF-8 byte slice.
//!
//! Offsets returned by the text view are always relative to the slice used to
//! open it. The view never allocates, and opening it does no scanning.
const grapheme_engine = @import("grapheme.zig");
const width_engine = @import("width.zig");
const wrap_engine = @import("wrap.zig");

pub const ByteOffset = struct {
    value: usize,
};

pub const Column = struct {
    value: usize,
};

pub const Span = struct {
    start: ByteOffset,
    end: ByteOffset,
};

pub const MeasuredSpan = struct {
    start: ByteOffset,
    end: ByteOffset,
    columns: u2,
    renderable: bool,
};

pub const Graphemes = struct {
    bytes: []const u8,

    pub fn iterator(self: Graphemes) Iterator(false) {
        return .{ .inner = grapheme_engine.iterator(self.bytes) };
    }

    pub fn measured(self: Graphemes) MeasuredGraphemes {
        return .{ .bytes = self.bytes };
    }
};

pub const MeasuredGraphemes = struct {
    bytes: []const u8,

    pub fn iterator(self: MeasuredGraphemes) Iterator(true) {
        return .{ .inner = grapheme_engine.iterator(self.bytes) };
    }
};

pub fn Iterator(comptime include_measure: bool) type {
    return struct {
        inner: grapheme_engine.Iterator,

        pub fn next(self: *@This()) ?if (include_measure) MeasuredSpan else Span {
            const span = self.inner.next() orelse return null;
            if (!include_measure) return .{
                .start = .{ .value = span.start },
                .end = .{ .value = span.end },
            };
            // The grapheme engine already measured this cluster while it
            // segmented it, and `grapheme.ClusterMeasure.finish` encodes the
            // whole measure: `3` is "one column, not renderable", `0` is "no
            // base", and `1`/`2` are renderable column counts. Decoding that
            // here is exact, and re-measuring the same bytes would decode and
            // classify every scalar of the cluster a second time.
            return .{
                .start = .{ .value = span.start },
                .end = .{ .value = span.end },
                .columns = if (span.columns == 3) 1 else @intCast(span.columns),
                .renderable = span.columns == 1 or span.columns == 2,
            };
        }
    };
}

pub const Line = struct {
    start: ByteOffset,
    end: ByteOffset,
    columns: Column,
};

pub const Wrapped = struct {
    bytes: []const u8,
    options: wrap_engine.Options,

    pub fn count(self: Wrapped) usize {
        var it = self.iterator();
        var result: usize = 0;
        while (it.next() != null) result += 1;
        return result;
    }

    pub fn iterator(self: Wrapped) WrappedIterator {
        return .{ .inner = wrap_engine.iterator(self.bytes, self.options) catch unreachable };
    }
};

pub const WrappedIterator = struct {
    inner: wrap_engine.Iterator,

    pub fn next(self: *WrappedIterator) ?Line {
        const line = self.inner.next() orelse return null;
        return .{
            .start = .{ .value = line.start },
            .end = .{ .value = line.end },
            .columns = .{ .value = line.columns },
        };
    }
};

/// A borrowed view of bytes read as plain text: every byte is content, and
/// terminal control sequences are not recognised.
///
/// If the bytes may contain ANSI escape sequences, strip them first. This view
/// measures `ESC`, `[`, `3`, `1`, `m` as ordinary characters, so
/// `"\x1b[31mred\x1b[0m"` reports width 10 rather than 3 and wrapping can
/// place a break inside the sequence, which corrupts the output. A `terminal`
/// view that understands escapes may be added later; until then this view
/// makes no attempt at it.
pub const Text = struct {
    bytes: []const u8,

    /// Extended grapheme clusters. Call `.measured()` on the result for
    /// per-cluster terminal columns.
    pub fn graphemes(self: Text) Graphemes {
        return .{ .bytes = self.bytes };
    }

    /// Total terminal columns, after the same filtering `measured()` applies:
    /// control characters and undecodable bytes occupy none.
    pub fn width(self: Text) usize {
        return width_engine.textWidth(self.bytes);
    }

    /// Hard line terminators, as byte extents. Paragraph content is the gaps
    /// between them; see the module docs.
    pub fn terminators(self: Text) Terminators {
        return .{ .bytes = self.bytes };
    }

    /// Greedy display lines within a finite column limit.
    pub fn wrap(self: Text, options: wrap_engine.Options) error{InvalidWidth}!Wrapped {
        if (options.max_columns == 0) return error.InvalidWidth;
        return .{ .bytes = self.bytes, .options = options };
    }
};

/// The seven Unicode hard line terminators, as byte extents. `\r\n` is one
/// terminator of length two.
///
/// | code point | UAX #14 class |
/// | --- | --- |
/// | `U+000A` LF, `U+000D` CR | LF, CR |
/// | `U+000B` VT, `U+000C` FF | BK |
/// | `U+0085` NEL | NL |
/// | `U+2028`, `U+2029` | BK |
///
/// Scanning raw bytes is sound: no grapheme cluster spans a terminator except
/// CRLF, because CR, LF and the rest are `GCB = Control`/`CR`/`LF` and GB4/GB5
/// force a break on both sides, while GB3 keeps CRLF together and this iterator
/// emits it as one span. An ASCII terminator byte can never appear inside a
/// multi-byte sequence, since UTF-8 continuation bytes are all >= 0x80.
pub const Terminators = struct {
    bytes: []const u8,

    /// Number of terminators. `\r\n` counts as one.
    pub fn count(self: Terminators) usize {
        var it = self.iterator();
        var n: usize = 0;
        while (it.next() != null) n += 1;
        return n;
    }

    pub fn iterator(self: Terminators) TerminatorIterator {
        return .{ .bytes = self.bytes };
    }
};

pub const TerminatorIterator = struct {
    bytes: []const u8,
    pos: usize = 0,

    /// Extent of the next terminator, or null at end of input. Unlike
    /// `line_break.Iterator`, nothing is reported at end of text: only
    /// terminators physically present in the bytes.
    pub fn next(self: *TerminatorIterator) ?Span {
        while (self.pos < self.bytes.len) {
            const start = self.pos;
            const byte = self.bytes[start];
            switch (byte) {
                '\r' => {
                    const end = if (start + 1 < self.bytes.len and self.bytes[start + 1] == '\n') start + 2 else start + 1;
                    self.pos = end;
                    return .{ .start = .{ .value = start }, .end = .{ .value = end } };
                },
                0x0A, 0x0B, 0x0C => {
                    self.pos = start + 1;
                    return .{ .start = .{ .value = start }, .end = .{ .value = start + 1 } };
                },
                // U+0085 NEL is C2 85; U+2028/U+2029 are E2 80 A8/A9. Verify
                // the whole sequence: a truncated lead byte is not a terminator.
                0xC2 => {
                    if (start + 1 < self.bytes.len and self.bytes[start + 1] == 0x85) {
                        self.pos = start + 2;
                        return .{ .start = .{ .value = start }, .end = .{ .value = start + 2 } };
                    }
                    self.pos = start + 1;
                },
                0xE2 => {
                    if (start + 2 < self.bytes.len and self.bytes[start + 1] == 0x80 and
                        (self.bytes[start + 2] == 0xA8 or self.bytes[start + 2] == 0xA9))
                    {
                        self.pos = start + 3;
                        return .{ .start = .{ .value = start }, .end = .{ .value = start + 3 } };
                    }
                    self.pos = start + 1;
                },
                else => self.pos = start + 1,
            }
        }
        return null;
    }
};
