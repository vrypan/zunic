//! Loss-tolerant UTF-8 stepping. Invalid input consumes exactly one byte.
const std = @import("std");

pub const Step = struct {
    len: usize,
    cp: ?u21,
};

pub fn step(bytes: []const u8) Step {
    if (bytes.len == 0) return .{ .len = 0, .cp = null };
    const len = std.unicode.utf8ByteSequenceLength(bytes[0]) catch
        return .{ .len = 1, .cp = null };
    if (len > bytes.len) return .{ .len = 1, .cp = null };
    const cp = std.unicode.utf8Decode(bytes[0..len]) catch
        return .{ .len = 1, .cp = null };
    return .{ .len = len, .cp = cp };
}
