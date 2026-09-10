//! Word boundaries for input already proven to contain only ASCII bytes.
//! ASCII has no ignored marks, Hebrew letters, Katakana, or regional indicators.
const std = @import("std");

// Called once per traversal; keep the vector scan out of the per-segment code.
pub noinline fn allAscii(bytes: []const u8) bool {
    const width = std.simd.suggestVectorLength(u8) orelse 16;
    var pos: usize = 0;
    while (bytes.len - pos >= width) : (pos += width) {
        const chunk: @Vector(width, u8) = bytes[pos..][0..width].*;
        if (@reduce(.Or, chunk > @as(@Vector(width, u8), @splat(0x7f)))) return false;
    }
    for (bytes[pos..]) |byte| if (byte >= 0x80) return false;
    return true;
}

pub const End = struct { offset: usize, is_word: bool };

inline fn wordByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}

inline fn bridge(prev: u8, punctuation: u8, following: u8) bool {
    return switch (punctuation) {
        '\'', '.' => (std.ascii.isAlphabetic(prev) and std.ascii.isAlphabetic(following)) or
            (std.ascii.isDigit(prev) and std.ascii.isDigit(following)),
        ':' => std.ascii.isAlphabetic(prev) and std.ascii.isAlphabetic(following),
        ',', ';' => std.ascii.isDigit(prev) and std.ascii.isDigit(following),
        else => false,
    };
}

/// Consume one segment, including non-word spans. `start` must be in bounds.
pub fn next(bytes: []const u8, start: usize) End {
    var end = start + 1;
    const first = bytes[start];
    if (wordByte(first)) {
        var is_word = first != '_';
        while (end < bytes.len) {
            const byte = bytes[end];
            if (wordByte(byte)) {
                is_word = is_word or byte != '_';
                end += 1;
            } else if (end + 1 < bytes.len and bridge(bytes[end - 1], byte, bytes[end + 1])) {
                is_word = true;
                end += 2;
            } else break;
        }
        return .{ .offset = end, .is_word = is_word };
    }
    if (first == ' ') {
        while (end < bytes.len and bytes[end] == ' ') : (end += 1) {}
    } else if (first == '\r' and end < bytes.len and bytes[end] == '\n') {
        end += 1;
    }
    return .{ .offset = end, .is_word = false };
}
