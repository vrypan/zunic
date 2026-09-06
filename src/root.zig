//! Allocation-free Unicode primitives for Zig terminal applications.
//!
//! Byte spans and terminal-column policy form the package's public boundary.
pub const utf8 = @import("utf8.zig");
const lens = @import("lens.zig");
const wrap_engine = @import("wrap.zig");
pub const line_break = @import("line_break.zig");

pub const ByteOffset = lens.ByteOffset;
pub const GraphemeIndex = lens.GraphemeIndex;
pub const Column = lens.Column;
pub const Span = lens.Span;
pub const MeasuredSpan = lens.MeasuredSpan;
pub const ColumnHit = lens.ColumnHit;
pub const Line = lens.Line;
pub const WrapOptions = wrap_engine.Options;
pub const Overflow = wrap_engine.Overflow;
pub const Wrapped = lens.Wrapped;

/// Open a grapheme lens.  It is a borrowed, zero-cost view; traversal occurs
/// only when calling `count`, `at`, or consuming its iterator.
pub fn graphemes(bytes: []const u8) lens.Graphemes(false) {
    return .{ .bytes = bytes };
}

/// Open a greedy display-line lens with a finite column limit.
pub fn wrap(bytes: []const u8, options: WrapOptions) error{InvalidWidth}!Wrapped {
    if (options.max_columns == 0) return error.InvalidWidth;
    return .{ .bytes = bytes, .options = options };
}

/// Open a line lens with no practical column limit.
pub fn lines(bytes: []const u8) Wrapped {
    return .{ .bytes = bytes, .options = .{ .max_columns = std.math.maxInt(usize) } };
}

pub fn width(bytes: []const u8) usize {
    return lens.width(bytes);
}
pub fn columnAt(bytes: []const u8, offset: ByteOffset) Column {
    return lens.columnAt(bytes, offset);
}
pub fn byteAt(bytes: []const u8, column: Column) ColumnHit {
    return lens.byteAt(bytes, column);
}

/// Instrumented wrapping is retained solely for zunic's work-bound tests.
pub const testing = struct {
    pub const instrumentedIterator = wrap_engine.instrumentedIterator;
};

const std = @import("std");
pub const build_options = @import("build_options");
