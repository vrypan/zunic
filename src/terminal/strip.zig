//! Allocation-free, UTF-agnostic escape removal into caller-owned storage.
const std = @import("std");
const escape = @import("escape.zig");

pub fn stripAnsi(bytes: []const u8, buffer: []u8) error{NoSpace}![]u8 {
    var read: usize = 0;
    var written: usize = 0;
    scan: while (read < bytes.len) {
        if (escape.end(bytes, read)) |end| {
            read = end;
            continue;
        }
        // Unroll the short prefix so dense commands do not pay for a
        // vector search or a per-byte run counter. A failed ESC is content.
        inline for (0..16) |index| {
            if (read == bytes.len) return buffer[0..written];
            if (index != 0 and bytes[read] == 0x1b) continue :scan;
            if (written == buffer.len) return error.NoSpace;
            buffer[written] = bytes[read];
            written += 1;
            read += 1;
        }
        // Longer runs use Zig's SIMD-capable search and a bulk copy.
        const end = std.mem.findScalarPos(u8, bytes, read, 0x1b) orelse bytes.len;
        const count = @min(end - read, buffer.len - written);
        std.mem.copyForwards(u8, buffer[written..][0..count], bytes[read..][0..count]);
        written += count;
        if (count < end - read) return error.NoSpace;
        read = end;
    }
    return buffer[0..written];
}
