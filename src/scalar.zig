//! Decoded Unicode scalar facts for consumers that need to compose rules.
//!
//! Invalid UTF-8 consumes one byte and has `codepoint == null`; its Unicode
//! properties use the package's existing malformed-input fallbacks.
const properties = @import("properties.zig");
const utf8 = @import("utf8.zig");

pub const Token = struct {
    start: usize,
    end: usize,
    codepoint: ?u21,
    grapheme: properties.GraphemeProperties,
    line_break: properties.LineBreak,
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
    const step = utf8.step(bytes[start..]);
    const cp = step.cp;
    return .{
        .start = start,
        .end = start + step.len,
        .codepoint = cp,
        .grapheme = if (cp) |value| properties.graphemeProperties(value) else .{ .gcb = .other, .incb = .none, .extended_pictographic = false },
        .line_break = if (cp) |value| properties.lineBreak(value) else .al,
    };
}
