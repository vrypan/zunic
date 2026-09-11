const std = @import("std");
const uucode = @import("uucode");

pub const name = "uucode";
pub const unicode_version = "17.0.0";
pub const Stats = struct { units: usize, checksum: u64 };

inline fn mix(hash: u64, value: usize) u64 {
    return (hash ^ @as(u64, @intCast(value))) *% 0x100000001b3;
}

pub inline fn utf8(bytes: []const u8) Stats {
    var it = uucode.utf8.Iterator.init(bytes);
    var units: usize = 0;
    var hash: u64 = 0xcbf29ce484222325;
    while (it.next()) |cp| : (units += 1)
        hash = mix(mix(hash, cp), it.i);
    return .{ .units = units, .checksum = hash };
}

pub inline fn graphemes(bytes: []const u8) Stats {
    var it = uucode.grapheme.utf8Iterator(bytes);
    var units: usize = 0;
    var hash: u64 = 0xcbf29ce484222325;
    while (it.nextGrapheme()) |span| : (units += 1)
        hash = mix(mix(hash, span.start), span.end);
    return .{ .units = units, .checksum = hash };
}

pub inline fn measured(bytes: []const u8) Stats {
    var it = uucode.grapheme.utf8Iterator(bytes);
    var units: usize = 0;
    var hash: u64 = 0xcbf29ce484222325;
    while (it.next_cp != null) : (units += 1) {
        const start = it.i;
        const columns = uucode.grapheme.wcwidthNext(&it);
        hash = mix(mix(mix(hash, start), it.i), columns);
    }
    return .{ .units = units, .checksum = hash };
}

pub inline fn width(bytes: []const u8) Stats {
    const value = uucode.grapheme.utf8Wcwidth(bytes);
    return .{ .units = value, .checksum = mix(0xcbf29ce484222325, value) };
}

pub fn dumpUtf8(out: *std.Io.Writer, bytes: []const u8) !void {
    var it = uucode.utf8.Iterator.init(bytes);
    while (it.next()) |cp| try out.print("{x}:{d},", .{ cp, it.i });
}

pub fn dumpGraphemes(out: *std.Io.Writer, bytes: []const u8) !void {
    var it = uucode.grapheme.utf8Iterator(bytes);
    while (it.nextGrapheme()) |span| try out.print("{d}:{d},", .{ span.start, span.end });
}

pub fn dumpMeasured(out: *std.Io.Writer, bytes: []const u8) !void {
    var it = uucode.grapheme.utf8Iterator(bytes);
    while (it.next_cp != null) {
        const start = it.i;
        const columns = uucode.grapheme.wcwidthNext(&it);
        try out.print("{d}:{d}:{d},", .{ start, it.i, columns });
    }
}

pub fn dumpWidth(out: *std.Io.Writer, bytes: []const u8) !void {
    try out.print("{d}", .{uucode.grapheme.utf8Wcwidth(bytes)});
}
