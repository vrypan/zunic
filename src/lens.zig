//! Public, question-shaped views over a borrowed UTF-8 byte slice.
//!
//! Offsets returned by a lens are always relative to the slice used to open
//! it.  Lenses never allocate and opening one does no scanning.
const grapheme_engine = @import("grapheme.zig");
const width_engine = @import("width.zig");
const wrap_engine = @import("wrap.zig");
const std = @import("std");

pub const ByteOffset = struct {
    value: usize,

    pub fn init(value: usize) ByteOffset {
        return .{ .value = value };
    }
};

pub const GraphemeIndex = struct {
    value: usize,

    pub fn init(value: usize) GraphemeIndex {
        return .{ .value = value };
    }
};

pub const Column = struct {
    value: usize,

    pub fn init(value: usize) Column {
        return .{ .value = value };
    }
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

pub const ColumnHit = struct {
    cluster: Span,
    column: Column,
};

pub fn Graphemes(comptime include_measure: bool) type {
    return struct {
        bytes: []const u8,

        const Self = @This();
        pub const Item = if (include_measure) MeasuredSpan else Span;

        pub fn count(self: Self) usize {
            var it = self.iterator();
            var result: usize = 0;
            while (it.next() != null) result += 1;
            return result;
        }

        pub fn iterator(self: Self) Iterator(include_measure) {
            return .{ .inner = grapheme_engine.iterator(self.bytes) };
        }

        pub fn at(self: Self, index: GraphemeIndex) ?Item {
            var it = self.iterator();
            var i: usize = 0;
            while (it.next()) |item| : (i += 1) if (i == index.value) return item;
            return null;
        }

        /// Fill caller-owned storage with spans and obtain O(1) `at`.
        /// The supplied buffer must hold every grapheme in this lens.
        pub fn indexed(self: Self, buffer: []Item) Indexed(include_measure) {
            std.debug.assert(buffer.len >= self.count());
            var it = self.iterator();
            var len: usize = 0;
            while (it.next()) |item| {
                buffer[len] = item;
                len += 1;
            }
            return .{ .items = buffer[0..len] };
        }

        pub fn measured(self: Self) Graphemes(true) {
            return .{ .bytes = self.bytes };
        }
    };
}

pub fn Iterator(comptime include_measure: bool) type {
    return struct {
        inner: grapheme_engine.Iterator,

        pub fn next(self: *@This()) ?if (include_measure) MeasuredSpan else Span {
            const span = self.inner.next() orelse return null;
            if (!include_measure) return .{
                .start = .init(span.start),
                .end = .init(span.end),
            };
            // The grapheme engine already measured this cluster while it
            // segmented it, and `grapheme.ClusterMeasure.finish` encodes the
            // whole measure: `3` is "one column, not renderable", `0` is "no
            // base", and `1`/`2` are renderable column counts. Decoding that
            // here is exact, and re-measuring the same bytes would decode and
            // classify every scalar of the cluster a second time.
            return .{
                .start = .init(span.start),
                .end = .init(span.end),
                .columns = if (span.columns == 3) 1 else @intCast(span.columns),
                .renderable = span.columns == 1 or span.columns == 2,
            };
        }
    };
}

pub fn Indexed(comptime include_measure: bool) type {
    return struct {
        items: []const if (include_measure) MeasuredSpan else Span,

        pub fn count(self: @This()) usize {
            return self.items.len;
        }
        pub fn at(self: @This(), index: GraphemeIndex) ?if (include_measure) MeasuredSpan else Span {
            if (index.value >= self.items.len) return null;
            return self.items[index.value];
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
            .start = .init(line.start),
            .end = .init(line.end),
            .columns = .init(line.columns),
        };
    }
};

pub fn width(bytes: []const u8) usize {
    return width_engine.textWidth(bytes);
}

/// Return the display column of `offset`.  Offsets inside a grapheme map to
/// that grapheme's start column; this intentionally makes the mapping
/// many-to-one.
pub fn columnAt(bytes: []const u8, offset: ByteOffset) Column {
    var it = (Graphemes(true){ .bytes = bytes }).iterator();
    var column: usize = 0;
    while (it.next()) |span| {
        if (offset.value < span.end.value) return .init(column);
        column += span.columns;
    }
    return .init(column);
}

/// Find the grapheme covering a display column.  At a straddled wide
/// grapheme, callers derive floor/ceil from `requested != hit.column`.
pub fn byteAt(bytes: []const u8, requested: Column) ColumnHit {
    var it = (Graphemes(true){ .bytes = bytes }).iterator();
    var column: usize = 0;
    while (it.next()) |measured| {
        const span = Span{ .start = measured.start, .end = measured.end };
        if (requested.value == column or requested.value < column + measured.columns)
            return .{ .cluster = span, .column = .init(column) };
        column += measured.columns;
    }
    const end = ByteOffset.init(bytes.len);
    return .{ .cluster = .{ .start = end, .end = end }, .column = .init(column) };
}
