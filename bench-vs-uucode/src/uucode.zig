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

pub inline fn terminalProperties(bytes: []const u8) Stats {
    var it = uucode.utf8.Iterator.init(bytes);
    var units: usize = 0;
    var hash: u64 = 0xcbf29ce484222325;
    while (it.next()) |cp| : (units += 1) {
        hash = mix(hash, it.i);
        hash = mix(hash, @intFromEnum(uucode.get(.east_asian_width, cp)));
        hash = mix(hash, @intFromBool(uucode.get(.is_emoji_presentation, cp)));
        hash = mix(hash, @intFromBool(uucode.get(.is_emoji_vs_base, cp)));
        hash = mix(hash, @intFromBool(uucode.get(.is_emoji_modifier, cp)));
        hash = mix(hash, @intFromBool(uucode.get(.is_emoji_modifier_base, cp)));
        hash = mix(hash, uucode.get(.wcwidth_standalone, cp));
        hash = mix(hash, @intFromBool(uucode.get(.wcwidth_zero_in_grapheme, cp)));
        hash = mix(hash, @intFromBool(uucode.get(.is_emoji_modifier, cp)));
    }
    return .{ .units = units, .checksum = hash };
}

pub inline fn caseFold(bytes: []const u8) Stats {
    var it = uucode.utf8.Iterator.init(bytes);
    var units: usize = 0;
    var hash: u64 = 0xcbf29ce484222325;
    while (it.next()) |cp| : (units += 1) {
        var identity: [1]u21 = undefined;
        const folded = uucode.get(.case_folding_full, cp).with(&identity, cp);
        hash = mix(hash, it.i);
        hash = mix(hash, folded.len);
        for (folded) |value| hash = mix(hash, value);
    }
    return .{ .units = units, .checksum = hash };
}

pub inline fn graphemeStream(bytes: []const u8) Stats {
    var it = uucode.utf8.Iterator.init(bytes);
    const first = it.next() orelse return .{ .units = 0, .checksum = 0xcbf29ce484222325 };
    var previous = first;
    var state: uucode.grapheme.BreakState = .default;
    var units: usize = 0;
    var hash: u64 = 0xcbf29ce484222325;
    while (it.next()) |current| : (units += 1) {
        const decision = uucode.grapheme.computeGraphemeBreak(
            uucode.get(.grapheme_break, previous),
            uucode.get(.grapheme_break, current),
            &state,
        );
        hash = mix(mix(hash, it.i), @intFromBool(decision));
        previous = current;
    }
    return .{ .units = units, .checksum = hash };
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
    var hash: u64 = 0xcbf29ce484222325;
    while (it.next()) |cp| : (units += 1)
        hash = mix(mix(hash, it.i), ghosttyScalarWidth(cp));
    return .{ .units = units, .checksum = hash };
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
        try out.print("{d}:{d}:{d}:{d}:{d}:{d}:{d}:{d}:{d},", .{
            it.i,
            @intFromEnum(uucode.get(.east_asian_width, cp)),
            @intFromBool(uucode.get(.is_emoji_presentation, cp)),
            @intFromBool(uucode.get(.is_emoji_vs_base, cp)),
            @intFromBool(uucode.get(.is_emoji_modifier, cp)),
            @intFromBool(uucode.get(.is_emoji_modifier_base, cp)),
            uucode.get(.wcwidth_standalone, cp),
            @intFromBool(uucode.get(.wcwidth_zero_in_grapheme, cp)),
            @intFromBool(uucode.get(.is_emoji_modifier, cp)),
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
