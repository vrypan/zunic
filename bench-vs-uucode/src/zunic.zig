const std = @import("std");
const zunic = @import("zunic");

pub const name = "zunic";
pub const unicode_version = "17.0.0";
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

pub inline fn terminalProperties(bytes: []const u8) Stats {
    var pos: usize = 0;
    var units: usize = 0;
    var hash: u64 = 0xcbf29ce484222325;
    while (pos < bytes.len) : (units += 1) {
        const step = zunic.utf8.step(bytes[pos..]);
        pos += step.len;
        const cp = step.cp orelse 0xfffd;
        const width_props = zunic.widthProperties(cp);
        hash = mix(hash, pos);
        hash = mix(hash, @intFromEnum(zunic.eastAsianWidth(cp)));
        hash = mix(hash, @intFromBool(zunic.isEmojiPresentation(cp)));
        hash = mix(hash, @intFromBool(zunic.isEmojiVariationBase(cp)));
        hash = mix(hash, @intFromBool(zunic.isEmojiModifier(cp)));
        hash = mix(hash, @intFromBool(zunic.isEmojiModifierBase(cp)));
        hash = mix(hash, width_props.standalone);
        hash = mix(hash, @intFromBool(width_props.zero_in_grapheme));
        hash = mix(hash, @intFromBool(width_props.emoji_modifier));
    }
    return .{ .units = units, .checksum = hash };
}

pub inline fn caseFold(bytes: []const u8) Stats {
    var pos: usize = 0;
    var units: usize = 0;
    var hash: u64 = 0xcbf29ce484222325;
    while (pos < bytes.len) : (units += 1) {
        const step = zunic.utf8.step(bytes[pos..]);
        pos += step.len;
        var folded = zunic.fullCaseFold(step.cp orelse 0xfffd);
        hash = mix(hash, pos);
        hash = mix(hash, folded.len);
        for (folded.slice()) |cp| hash = mix(hash, cp);
    }
    return .{ .units = units, .checksum = hash };
}

pub inline fn graphemeStream(bytes: []const u8) Stats {
    if (bytes.len == 0) return .{ .units = 0, .checksum = 0xcbf29ce484222325 };
    const first = zunic.utf8.step(bytes);
    var pos = first.len;
    var previous = first.cp orelse 0xfffd;
    var state: zunic.GraphemeState = .{};
    var units: usize = 0;
    var hash: u64 = 0xcbf29ce484222325;
    while (pos < bytes.len) : (units += 1) {
        const step = zunic.utf8.step(bytes[pos..]);
        pos += step.len;
        const current = step.cp orelse 0xfffd;
        hash = mix(hash, pos);
        hash = mix(hash, @intFromBool(zunic.graphemeBreak(previous, current, &state)));
        previous = current;
    }
    return .{ .units = units, .checksum = hash };
}

inline fn ghosttyScalarWidth(cp: u21) u2 {
    const width_props = zunic.widthProperties(cp);
    if (width_props.zero_in_grapheme and !width_props.emoji_modifier and zunic.graphemeProperties(cp).gcb != .prepend) return 0;
    return @min(2, width_props.standalone);
}

pub inline fn ghosttyWidth(bytes: []const u8) Stats {
    var pos: usize = 0;
    var units: usize = 0;
    var hash: u64 = 0xcbf29ce484222325;
    while (pos < bytes.len) : (units += 1) {
        const step = zunic.utf8.step(bytes[pos..]);
        pos += step.len;
        hash = mix(mix(hash, pos), ghosttyScalarWidth(step.cp orelse 0xfffd));
    }
    return .{ .units = units, .checksum = hash };
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
        const width_props = zunic.widthProperties(cp);
        try out.print("{d}:{d}:{d}:{d}:{d}:{d}:{d}:{d}:{d},", .{
            pos,
            @intFromEnum(zunic.eastAsianWidth(cp)),
            @intFromBool(zunic.isEmojiPresentation(cp)),
            @intFromBool(zunic.isEmojiVariationBase(cp)),
            @intFromBool(zunic.isEmojiModifier(cp)),
            @intFromBool(zunic.isEmojiModifierBase(cp)),
            width_props.standalone,
            @intFromBool(width_props.zero_in_grapheme),
            @intFromBool(width_props.emoji_modifier),
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
