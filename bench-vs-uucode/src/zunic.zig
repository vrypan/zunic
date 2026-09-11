const std = @import("std");
const zunic = @import("zunic");

pub const name = "zunic";
pub const unicode_version = "16.0.0";
pub const Stats = struct { units: usize, checksum: u64 };

inline fn mix(hash: u64, value: usize) u64 {
    return (hash ^ @as(u64, @intCast(value))) *% 0x100000001b3;
}

pub inline fn utf8(bytes: []const u8) Stats {
    var pos: usize = 0;
    var units: usize = 0;
    var hash: u64 = 0xcbf29ce484222325;
    while (pos < bytes.len) : (units += 1) {
        const step = zunic.utf8.step(bytes[pos..]);
        pos += step.len;
        hash = mix(mix(hash, step.cp orelse 0xfffd), pos);
    }
    return .{ .units = units, .checksum = hash };
}

pub inline fn graphemes(bytes: []const u8) Stats {
    var it = zunic.text(bytes).graphemes().iterator();
    var units: usize = 0;
    var hash: u64 = 0xcbf29ce484222325;
    while (it.next()) |span| : (units += 1)
        hash = mix(mix(hash, span.start.value), span.end.value);
    return .{ .units = units, .checksum = hash };
}

pub inline fn measured(bytes: []const u8) Stats {
    var it = zunic.text(bytes).graphemes().measured().iterator();
    var units: usize = 0;
    var hash: u64 = 0xcbf29ce484222325;
    while (it.next()) |span| : (units += 1)
        hash = mix(mix(mix(hash, span.start.value), span.end.value), span.columns);
    return .{ .units = units, .checksum = hash };
}

pub inline fn width(bytes: []const u8) Stats {
    const value = zunic.text(bytes).width();
    return .{ .units = value, .checksum = mix(0xcbf29ce484222325, value) };
}

pub fn dumpUtf8(out: *std.Io.Writer, bytes: []const u8) !void {
    var pos: usize = 0;
    while (pos < bytes.len) {
        const step = zunic.utf8.step(bytes[pos..]);
        pos += step.len;
        try out.print("{x}:{d},", .{ step.cp orelse 0xfffd, pos });
    }
}

pub fn dumpGraphemes(out: *std.Io.Writer, bytes: []const u8) !void {
    var it = zunic.text(bytes).graphemes().iterator();
    while (it.next()) |span| try out.print("{d}:{d},", .{ span.start.value, span.end.value });
}

pub fn dumpMeasured(out: *std.Io.Writer, bytes: []const u8) !void {
    var it = zunic.text(bytes).graphemes().measured().iterator();
    while (it.next()) |span| try out.print("{d}:{d}:{d},", .{ span.start.value, span.end.value, span.columns });
}

pub fn dumpWidth(out: *std.Io.Writer, bytes: []const u8) !void {
    try out.print("{d}", .{zunic.text(bytes).width()});
}
