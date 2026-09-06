//! Decoded Unicode scalar facts for consumers that need to compose rules.
//!
//! Invalid UTF-8 consumes one byte and has `codepoint == null`; its Unicode
//! properties use the package's existing malformed-input fallbacks.
const properties = @import("properties.zig");
const table = @import("tables.zig");
const utf8 = @import("utf8.zig");

pub const Token = struct {
    start: usize,
    end: usize,
    codepoint: ?u21,
    grapheme: properties.GraphemeProperties,
    line_break: properties.LineBreak,
    cell_width: u2,
};

pub const Iterator = struct {
    bytes: []const u8,
    offset: usize = 0,

    pub fn next(self: *Iterator) ?Token {
        if (self.offset == self.bytes.len) return null;
        const start = self.offset;
        const token = at(self.bytes, start);
        self.offset = token.end;
        return token;
    }
};

pub fn iterator(bytes: []const u8) Iterator {
    return .{ .bytes = bytes };
}

pub fn at(bytes: []const u8, start: usize) Token {
    // ASCII is one byte, one scalar, one column, and both property tables
    // index it directly, so the decode and the range searches are skipped.
    // This is the same result the general path below produces.
    if (start < bytes.len and bytes[start] < 0x80) return .{
        .start = start,
        .end = start + 1,
        .codepoint = bytes[start],
        .grapheme = properties.grapheme_ascii[bytes[start]],
        .line_break = properties.line_break_ascii[bytes[start]],
        .cell_width = 1,
    };

    const step = utf8.step(bytes[start..]);
    const cp = step.cp;
    return .{
        .start = start,
        .end = start + step.len,
        .codepoint = cp,
        .grapheme = if (cp) |value| properties.graphemeProperties(value) else .{ .gcb = .other, .incb = .none, .extended_pictographic = false },
        .line_break = if (cp) |value| properties.lineBreak(value) else .al,
        .cell_width = if (cp) |value| codepointWidth(value) else 0,
    };
}

pub fn codepointWidth(cp: u21) u2 {
    if (cp < 0x300) return 1;
    if (inRanges(&table.zero_width, cp)) return 0;
    if (inRanges(&table.wide, cp)) return 2;
    return 1;
}

fn inRanges(ranges: []const table.Range, cp: u21) bool {
    var lo: usize = 0;
    var hi: usize = ranges.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const range = ranges[mid];
        if (cp < range.lo) hi = mid else if (cp > range.hi) lo = mid + 1 else return true;
    }
    return false;
}
