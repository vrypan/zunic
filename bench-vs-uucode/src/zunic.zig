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
    var sums: [10]usize = @splat(0);
    while (pos < bytes.len) : (units += 1) {
        const step = zunic.utf8.step(bytes[pos..]);
        pos += step.len;
        const cp = step.cp orelse 0xfffd;
        const props = zunic.cp(cp).terminal();
        sums[0] +%= pos;
        sums[1] +%= @intFromEnum(props.eastAsianWidth);
        sums[2] +%= @intFromBool(props.isEmojiPresentation);
        sums[3] +%= @intFromBool(props.isEmojiVariationBase);
        sums[4] +%= @intFromBool(props.isEmojiModifier);
        sums[5] +%= @intFromBool(props.isEmojiModifierBase);
        sums[6] +%= props.standalone;
        sums[7] +%= @intFromBool(props.zeroInGrapheme);
        sums[8] +%= @intFromBool(props.isEmoji);
        sums[9] +%= @intFromBool(props.isEmojiComponent);
    }
    return .{ .units = units, .checksum = finishSums(sums) };
}

pub inline fn terminalLookup(codepoints: []const u21) Stats {
    var sums: [10]usize = @splat(0);
    for (codepoints) |cp| {
        const props = zunic.cp(cp).terminal();
        sums[0] +%= cp;
        sums[1] +%= @intFromEnum(props.eastAsianWidth);
        sums[2] +%= @intFromBool(props.isEmojiPresentation);
        sums[3] +%= @intFromBool(props.isEmojiVariationBase);
        sums[4] +%= @intFromBool(props.isEmojiModifier);
        sums[5] +%= @intFromBool(props.isEmojiModifierBase);
        sums[6] +%= props.standalone;
        sums[7] +%= @intFromBool(props.zeroInGrapheme);
        sums[8] +%= @intFromBool(props.isEmoji);
        sums[9] +%= @intFromBool(props.isEmojiComponent);
    }
    return .{ .units = codepoints.len, .checksum = finishSums(sums) };
}

pub inline fn caseFold(bytes: []const u8) Stats {
    var pos: usize = 0;
    var units: usize = 0;
    var sums: [3]usize = @splat(0);
    while (pos < bytes.len) : (units += 1) {
        const step = zunic.utf8.step(bytes[pos..]);
        pos += step.len;
        var folded = zunic.cp(step.cp orelse 0xfffd).fullCaseFold();
        sums[0] +%= pos;
        sums[1] +%= folded.len;
        for (folded.slice()) |cp| sums[2] +%= cp;
    }
    return .{ .units = units, .checksum = finishSums(sums) };
}

const SimpleCase = enum { uppercase, lowercase, titlecase };

inline fn simpleCase(codepoints: []const u21, comptime operation: SimpleCase) Stats {
    var sums: [2]usize = @splat(0);
    for (codepoints) |cp| {
        const mapped = switch (operation) {
            .uppercase => zunic.cp(cp).simpleUppercase(),
            .lowercase => zunic.cp(cp).simpleLowercase(),
            .titlecase => zunic.cp(cp).simpleTitlecase(),
        };
        sums[0] +%= cp;
        sums[1] +%= mapped;
    }
    return .{ .units = codepoints.len, .checksum = finishSums(sums) };
}

pub inline fn simpleUppercase(codepoints: []const u21) Stats {
    return simpleCase(codepoints, .uppercase);
}

pub inline fn simpleLowercase(codepoints: []const u21) Stats {
    return simpleCase(codepoints, .lowercase);
}

pub inline fn simpleTitlecase(codepoints: []const u21) Stats {
    return simpleCase(codepoints, .titlecase);
}

pub inline fn numericProperties(codepoints: []const u21) Stats {
    var sums: [4]usize = @splat(0);
    for (codepoints) |cp| {
        sums[0] +%= cp;
        if (zunic.cp(cp).numeric()) |value| {
            sums[1] +%= @intFromEnum(value.kind) + 1;
            sums[2] +%= @as(usize, @bitCast(value.numerator));
            sums[3] +%= value.denominator;
        }
    }
    return .{ .units = codepoints.len, .checksum = finishSums(sums) };
}

pub inline fn combiningClass(codepoints: []const u21) Stats {
    var sums: [2]usize = @splat(0);
    for (codepoints) |cp| {
        sums[0] +%= cp;
        sums[1] +%= zunic.cp(cp).canonicalCombiningClass();
    }
    return .{ .units = codepoints.len, .checksum = finishSums(sums) };
}

pub inline fn decomposition(codepoints: []const u21) Stats {
    var sums: [5]usize = @splat(0);
    for (codepoints) |cp| {
        sums[0] +%= cp;
        if (zunic.cp(cp).decomposition()) |value| {
            sums[1] +%= 1;
            sums[2] +%= @intFromEnum(value.type);
            sums[3] +%= value.mapping.len;
            for (value.mapping) |mapped| sums[4] +%= mapped;
        }
    }
    return .{ .units = codepoints.len, .checksum = finishSums(sums) };
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
    const width_props = zunic.cp(cp).terminal();
    if (width_props.zeroInGrapheme and !width_props.isEmojiModifier and zunic.cp(cp).grapheme().gcb != .prepend) return 0;
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
        const props = zunic.cp(cp).terminal();
        try out.print("{d}:{d}:{d}:{d}:{d}:{d}:{d}:{d}:{d}:{d},", .{
            pos,
            @intFromEnum(props.eastAsianWidth),
            @intFromBool(props.isEmojiPresentation),
            @intFromBool(props.isEmojiVariationBase),
            @intFromBool(props.isEmoji),
            @intFromBool(props.isEmojiComponent),
            @intFromBool(props.isEmojiModifierBase),
            props.standalone,
            @intFromBool(props.zeroInGrapheme),
            @intFromBool(props.isEmojiModifier),
        });
    }
}

pub fn dumpTerminalLookup(out: *std.Io.Writer, codepoints: []const u21) !void {
    for (codepoints) |cp| {
        const props = zunic.cp(cp).terminal();
        try out.print("{x}:{d}:{d}:{d}:{d}:{d}:{d}:{d}:{d}:{d},", .{
            cp,
            @intFromEnum(props.eastAsianWidth),
            @intFromBool(props.isEmojiPresentation),
            @intFromBool(props.isEmojiVariationBase),
            @intFromBool(props.isEmojiModifier),
            @intFromBool(props.isEmojiModifierBase),
            props.standalone,
            @intFromBool(props.zeroInGrapheme),
            @intFromBool(props.isEmoji),
            @intFromBool(props.isEmojiComponent),
        });
    }
}

pub fn dumpCaseFold(out: *std.Io.Writer, bytes: []const u8) !void {
    var pos: usize = 0;
    while (pos < bytes.len) {
        const step = zunic.utf8.step(bytes[pos..]);
        pos += step.len;
        var folded = zunic.cp(step.cp orelse 0xfffd).fullCaseFold();
        try out.print("{d}:", .{pos});
        for (folded.slice()) |cp| try out.print("{x}.", .{cp});
        try out.writeByte(',');
    }
}

fn dumpSimpleCase(out: *std.Io.Writer, codepoints: []const u21, comptime operation: SimpleCase) !void {
    for (codepoints) |cp| {
        const mapped = switch (operation) {
            .uppercase => zunic.cp(cp).simpleUppercase(),
            .lowercase => zunic.cp(cp).simpleLowercase(),
            .titlecase => zunic.cp(cp).simpleTitlecase(),
        };
        try out.print("{x}:{x},", .{ cp, mapped });
    }
}

pub fn dumpSimpleUppercase(out: *std.Io.Writer, codepoints: []const u21) !void {
    return dumpSimpleCase(out, codepoints, .uppercase);
}

pub fn dumpSimpleLowercase(out: *std.Io.Writer, codepoints: []const u21) !void {
    return dumpSimpleCase(out, codepoints, .lowercase);
}

pub fn dumpSimpleTitlecase(out: *std.Io.Writer, codepoints: []const u21) !void {
    return dumpSimpleCase(out, codepoints, .titlecase);
}

pub fn dumpNumericProperties(out: *std.Io.Writer, codepoints: []const u21) !void {
    for (codepoints) |cp| {
        if (zunic.cp(cp).numeric()) |value| {
            try out.print("{x}:{d}:{d}:{d},", .{
                cp, @intFromEnum(value.kind), value.numerator, value.denominator,
            });
        } else try out.print("{x}:n,", .{cp});
    }
}

pub fn dumpCombiningClass(out: *std.Io.Writer, codepoints: []const u21) !void {
    for (codepoints) |cp|
        try out.print("{x}:{d},", .{ cp, zunic.cp(cp).canonicalCombiningClass() });
}

pub fn dumpDecomposition(out: *std.Io.Writer, codepoints: []const u21) !void {
    for (codepoints) |cp| {
        if (zunic.cp(cp).decomposition()) |value| {
            try out.print("{x}:{d}:", .{ cp, @intFromEnum(value.type) });
            for (value.mapping) |mapped| try out.print("{x}.", .{mapped});
            try out.writeByte(',');
        } else try out.print("{x}:n,", .{cp});
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
