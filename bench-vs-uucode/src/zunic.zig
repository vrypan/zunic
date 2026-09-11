const std = @import("std");
const zunic = @import("zunic");

pub const name = "zunic";
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
    var pos: usize = 0;
    var units: usize = 0;
    var sums: [2]usize = @splat(0);
    while (pos < bytes.len) : (units += 1) {
        const step = zunic.utf8.step(bytes[pos..]);
        pos += step.len;
        sums[0] +%= step.cp orelse 0xfffd;
        sums[1] +%= pos;
    }
    return .{ .units = units, .checksum = finishSums(sums) };
}

pub inline fn graphemes(bytes: []const u8) Stats {
    var it = zunic.text(bytes).graphemes().iterator();
    var units: usize = 0;
    var sums: [2]usize = @splat(0);
    while (it.next()) |span| : (units += 1) {
        sums[0] +%= span.start.value;
        sums[1] +%= span.end.value;
    }
    return .{ .units = units, .checksum = finishSums(sums) };
}

pub inline fn measured(bytes: []const u8) Stats {
    var it = zunic.text(bytes).graphemes().measured().iterator();
    var units: usize = 0;
    var sums: [3]usize = @splat(0);
    while (it.next()) |span| : (units += 1) {
        sums[0] +%= span.start.value;
        sums[1] +%= span.end.value;
        sums[2] +%= span.columns;
    }
    return .{ .units = units, .checksum = finishSums(sums) };
}

pub inline fn width(bytes: []const u8) Stats {
    const value = zunic.text(bytes).width();
    return .{ .units = value, .checksum = mix(0xcbf29ce484222325, value) };
}

pub inline fn terminalProperties(bytes: []const u8) Stats {
    var pos: usize = 0;
    var units: usize = 0;
    var sums: [9]usize = @splat(0);
    while (pos < bytes.len) : (units += 1) {
        const step = zunic.utf8.step(bytes[pos..]);
        pos += step.len;
        const cp = step.cp orelse 0xfffd;
        const props = zunic.terminalProperties(cp);
        sums[0] +%= pos;
        sums[1] +%= @intFromEnum(props.east_asian_width);
        sums[2] +%= @intFromBool(props.emoji_presentation);
        sums[3] +%= @intFromBool(props.emoji_variation_base);
        sums[4] +%= @intFromBool(props.emoji_modifier);
        sums[5] +%= @intFromBool(props.emoji_modifier_base);
        sums[6] +%= props.standalone;
        sums[7] +%= @intFromBool(props.zero_in_grapheme);
        sums[8] +%= @intFromBool(props.emoji_modifier);
    }
    return .{ .units = units, .checksum = finishSums(sums) };
}

pub inline fn caseFold(bytes: []const u8) Stats {
    var pos: usize = 0;
    var units: usize = 0;
    var sums: [3]usize = @splat(0);
    while (pos < bytes.len) : (units += 1) {
        const step = zunic.utf8.step(bytes[pos..]);
        pos += step.len;
        var folded = zunic.fullCaseFold(step.cp orelse 0xfffd);
        sums[0] +%= pos;
        sums[1] +%= folded.len;
        for (folded.slice()) |cp| sums[2] +%= cp;
    }
    return .{ .units = units, .checksum = finishSums(sums) };
}

pub inline fn graphemeStream(bytes: []const u8) Stats {
    if (bytes.len == 0) return .{ .units = 0, .checksum = 0xcbf29ce484222325 };
    const first = zunic.utf8.step(bytes);
    var pos = first.len;
    var previous = first.cp orelse 0xfffd;
    var state: zunic.GraphemeState = .{};
    var units: usize = 0;
    var sums: [2]usize = @splat(0);
    while (pos < bytes.len) : (units += 1) {
        const step = zunic.utf8.step(bytes[pos..]);
        pos += step.len;
        const current = step.cp orelse 0xfffd;
        sums[0] +%= pos;
        sums[1] +%= @intFromBool(zunic.graphemeBreak(previous, current, &state));
        previous = current;
    }
    return .{ .units = units, .checksum = finishSums(sums) };
}

inline fn ghosttyScalarWidth(cp: u21) u2 {
    const width_props = zunic.widthProperties(cp);
    if (width_props.zero_in_grapheme and !width_props.emoji_modifier and zunic.graphemeProperties(cp).gcb != .prepend) return 0;
    return @min(2, width_props.standalone);
}

pub inline fn ghosttyWidth(bytes: []const u8) Stats {
    var pos: usize = 0;
    var units: usize = 0;
    var sums: [2]usize = @splat(0);
    while (pos < bytes.len) : (units += 1) {
        const step = zunic.utf8.step(bytes[pos..]);
        pos += step.len;
        sums[0] +%= pos;
        sums[1] +%= ghosttyScalarWidth(step.cp orelse 0xfffd);
    }
    return .{ .units = units, .checksum = finishSums(sums) };
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

pub fn dumpTerminalProperties(out: *std.Io.Writer, bytes: []const u8) !void {
    var pos: usize = 0;
    while (pos < bytes.len) {
        const step = zunic.utf8.step(bytes[pos..]);
        pos += step.len;
        const cp = step.cp orelse 0xfffd;
        const props = zunic.terminalProperties(cp);
        try out.print("{d}:{d}:{d}:{d}:{d}:{d}:{d}:{d}:{d},", .{
            pos,
            @intFromEnum(props.east_asian_width),
            @intFromBool(props.emoji_presentation),
            @intFromBool(props.emoji_variation_base),
            @intFromBool(props.emoji_modifier),
            @intFromBool(props.emoji_modifier_base),
            props.standalone,
            @intFromBool(props.zero_in_grapheme),
            @intFromBool(props.emoji_modifier),
        });
    }
}

pub fn dumpCaseFold(out: *std.Io.Writer, bytes: []const u8) !void {
    var pos: usize = 0;
    while (pos < bytes.len) {
        const step = zunic.utf8.step(bytes[pos..]);
        pos += step.len;
        var folded = zunic.fullCaseFold(step.cp orelse 0xfffd);
        try out.print("{d}:", .{pos});
        for (folded.slice()) |cp| try out.print("{x}.", .{cp});
        try out.writeByte(',');
    }
}

pub fn dumpGraphemeStream(out: *std.Io.Writer, bytes: []const u8) !void {
    if (bytes.len == 0) return;
    const first = zunic.utf8.step(bytes);
    var pos = first.len;
    var previous = first.cp orelse 0xfffd;
    var state: zunic.GraphemeState = .{};
    while (pos < bytes.len) {
        const step = zunic.utf8.step(bytes[pos..]);
        pos += step.len;
        const current = step.cp orelse 0xfffd;
        try out.print("{d}:{d},", .{ pos, @intFromBool(zunic.graphemeBreak(previous, current, &state)) });
        previous = current;
    }
}

pub fn dumpGhosttyWidth(out: *std.Io.Writer, bytes: []const u8) !void {
    var pos: usize = 0;
    while (pos < bytes.len) {
        const step = zunic.utf8.step(bytes[pos..]);
        pos += step.len;
        try out.print("{d}:{d},", .{ pos, ghosttyScalarWidth(step.cp orelse 0xfffd) });
    }
}
