const std = @import("std");
const uucode = @import("uucode");

pub const name = "uucode";
pub const unicode_version = "17.0.0";
pub const Stats = struct { units: usize, checksum: u64 };

inline fn mix(hash: u64, value: usize) u64 {
    return (hash ^ @as(u64, @intCast(value))) *% 0x100000001b3;
}

inline fn finishSums(sums: anytype) u64 {
    var hash: u64 = 0xcbf29ce484222325;
    for (sums) |sum| hash = mix(hash, sum);
    return hash;
}

pub inline fn utf8(bytes: []const u8) Stats {
    var it = uucode.utf8.Iterator.init(bytes);
    var units: usize = 0;
    var sums: [2]usize = @splat(0);
    while (it.next()) |cp| : (units += 1) {
        sums[0] +%= cp;
        sums[1] +%= it.i;
    }
    return .{ .units = units, .checksum = finishSums(sums) };
}

pub inline fn graphemes(bytes: []const u8) Stats {
    var it = uucode.grapheme.utf8Iterator(bytes);
    var units: usize = 0;
    var sums: [2]usize = @splat(0);
    while (it.nextGrapheme()) |span| : (units += 1) {
        sums[0] +%= span.start;
        sums[1] +%= span.end;
    }
    return .{ .units = units, .checksum = finishSums(sums) };
}

pub inline fn measured(bytes: []const u8) Stats {
    var it = uucode.grapheme.utf8Iterator(bytes);
    var units: usize = 0;
    var sums: [3]usize = @splat(0);
    while (it.next_cp != null) : (units += 1) {
        const start = it.i;
        const columns = uucode.grapheme.wcwidthNext(&it);
        sums[0] +%= start;
        sums[1] +%= it.i;
        sums[2] +%= columns;
    }
    return .{ .units = units, .checksum = finishSums(sums) };
}

pub inline fn width(bytes: []const u8) Stats {
    const value = uucode.grapheme.utf8Wcwidth(bytes);
    return .{ .units = value, .checksum = mix(0xcbf29ce484222325, value) };
}

pub inline fn terminalProperties(bytes: []const u8) Stats {
    var it = uucode.utf8.Iterator.init(bytes);
    var units: usize = 0;
    var sums: [9]usize = @splat(0);
    while (it.next()) |cp| : (units += 1) {
        const props = uucode.getAll("0", cp);
        sums[0] +%= it.i;
        sums[1] +%= @intFromEnum(props.east_asian_width);
        sums[2] +%= @intFromBool(props.is_emoji_presentation);
        sums[3] +%= @intFromBool(props.is_emoji_vs_base);
        sums[4] +%= @intFromBool(props.is_emoji_modifier);
        sums[5] +%= @intFromBool(props.is_emoji_modifier_base);
        sums[6] +%= props.wcwidth_standalone;
        sums[7] +%= @intFromBool(props.wcwidth_zero_in_grapheme);
        sums[8] +%= @intFromBool(props.is_emoji_modifier);
    }
    return .{ .units = units, .checksum = finishSums(sums) };
}

pub inline fn caseFold(bytes: []const u8) Stats {
    var it = uucode.utf8.Iterator.init(bytes);
    var units: usize = 0;
    var sums: [3]usize = @splat(0);
    while (it.next()) |cp| : (units += 1) {
        var identity: [1]u21 = undefined;
        const folded = uucode.get(.case_folding_full, cp).with(&identity, cp);
        sums[0] +%= it.i;
        sums[1] +%= folded.len;
        for (folded) |value| sums[2] +%= value;
    }
    return .{ .units = units, .checksum = finishSums(sums) };
}

pub inline fn graphemeStream(bytes: []const u8) Stats {
    var it = uucode.utf8.Iterator.init(bytes);
    const first = it.next() orelse return .{ .units = 0, .checksum = 0xcbf29ce484222325 };
    var previous = first;
    var state: uucode.grapheme.BreakState = .default;
    var units: usize = 0;
    var sums: [2]usize = @splat(0);
    while (it.next()) |current| : (units += 1) {
        const decision = uucode.grapheme.computeGraphemeBreak(
            uucode.get(.grapheme_break, previous),
            uucode.get(.grapheme_break, current),
            &state,
        );
        sums[0] +%= it.i;
        sums[1] +%= @intFromBool(decision);
        previous = current;
    }
    return .{ .units = units, .checksum = finishSums(sums) };
}

inline fn ghosttyScalarWidth(cp: u21) u2 {
    const standalone = uucode.get(.wcwidth_standalone, cp);
    if (uucode.get(.wcwidth_zero_in_grapheme, cp) and
        !uucode.get(.is_emoji_modifier, cp) and
        uucode.get(.grapheme_break_no_control, cp) != .prepend) return 0;
    return @min(2, standalone);
}

pub inline fn ghosttyWidth(bytes: []const u8) Stats {
    var it = uucode.utf8.Iterator.init(bytes);
    var units: usize = 0;
    var sums: [2]usize = @splat(0);
    while (it.next()) |cp| : (units += 1) {
        sums[0] +%= it.i;
        sums[1] +%= ghosttyScalarWidth(cp);
    }
    return .{ .units = units, .checksum = finishSums(sums) };
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

pub fn dumpTerminalProperties(out: *std.Io.Writer, bytes: []const u8) !void {
    var it = uucode.utf8.Iterator.init(bytes);
    while (it.next()) |cp| {
        const props = uucode.getAll("0", cp);
        try out.print("{d}:{d}:{d}:{d}:{d}:{d}:{d}:{d}:{d},", .{
            it.i,
            @intFromEnum(props.east_asian_width),
            @intFromBool(props.is_emoji_presentation),
            @intFromBool(props.is_emoji_vs_base),
            @intFromBool(props.is_emoji_modifier),
            @intFromBool(props.is_emoji_modifier_base),
            props.wcwidth_standalone,
            @intFromBool(props.wcwidth_zero_in_grapheme),
            @intFromBool(props.is_emoji_modifier),
        });
    }
}

pub fn dumpCaseFold(out: *std.Io.Writer, bytes: []const u8) !void {
    var it = uucode.utf8.Iterator.init(bytes);
    while (it.next()) |cp| {
        var identity: [1]u21 = undefined;
        const folded = uucode.get(.case_folding_full, cp).with(&identity, cp);
        try out.print("{d}:", .{it.i});
        for (folded) |value| try out.print("{x}.", .{value});
        try out.writeByte(',');
    }
}

pub fn dumpGraphemeStream(out: *std.Io.Writer, bytes: []const u8) !void {
    var it = uucode.utf8.Iterator.init(bytes);
    var previous = it.next() orelse return;
    var state: uucode.grapheme.BreakState = .default;
    while (it.next()) |current| {
        const decision = uucode.grapheme.computeGraphemeBreak(
            uucode.get(.grapheme_break, previous),
            uucode.get(.grapheme_break, current),
            &state,
        );
        try out.print("{d}:{d},", .{ it.i, @intFromBool(decision) });
        previous = current;
    }
}

pub fn dumpGhosttyWidth(out: *std.Io.Writer, bytes: []const u8) !void {
    var it = uucode.utf8.Iterator.init(bytes);
    while (it.next()) |cp| try out.print("{d}:{d},", .{ it.i, ghosttyScalarWidth(cp) });
}
