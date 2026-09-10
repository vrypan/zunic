//! Whether a byte slice is entirely ASCII.
//!
//! A plain byte-range test, not Unicode validation and not a printable-text
//! check: every byte below 0x80 counts, including NUL, ESC, and DEL, and a
//! high byte fails the check whether it belongs to valid UTF-8 or to
//! malformed input.
const std = @import("std");

/// True iff every byte in `bytes` is below 0x80. Empty input is ASCII.
///
/// Bounded vector scan with a scalar tail. Callers that use this to pick a
/// faster path for confirmed-ASCII input call it once per traversal, so it
/// is kept out of any per-byte or per-segment hot loop rather than inlined
/// into one.
pub noinline fn isAscii(bytes: []const u8) bool {
    const width = std.simd.suggestVectorLength(u8) orelse 16;
    var pos: usize = 0;
    while (bytes.len - pos >= width) : (pos += width) {
        const chunk: @Vector(width, u8) = bytes[pos..][0..width].*;
        if (@reduce(.Or, chunk > @as(@Vector(width, u8), @splat(0x7f)))) return false;
    }
    for (bytes[pos..]) |byte| if (byte >= 0x80) return false;
    return true;
}
