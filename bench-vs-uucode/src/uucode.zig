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
    var sums: [10]usize = @splat(0);
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
        sums[8] +%= @intFromBool(props.is_emoji);
        sums[9] +%= @intFromBool(props.is_emoji_component);
    }
    return .{ .units = units, .checksum = finishSums(sums) };
}

pub inline fn terminalLookup(codepoints: []const u21) Stats {
    var sums: [10]usize = @splat(0);
    for (codepoints) |cp| {
        const props = uucode.getAll("0", cp);
        sums[0] +%= cp;
        sums[1] +%= @intFromEnum(props.east_asian_width);
        sums[2] +%= @intFromBool(props.is_emoji_presentation);
        sums[3] +%= @intFromBool(props.is_emoji_vs_base);
        sums[4] +%= @intFromBool(props.is_emoji_modifier);
        sums[5] +%= @intFromBool(props.is_emoji_modifier_base);
        sums[6] +%= props.wcwidth_standalone;
        sums[7] +%= @intFromBool(props.wcwidth_zero_in_grapheme);
        sums[8] +%= @intFromBool(props.is_emoji);
        sums[9] +%= @intFromBool(props.is_emoji_component);
    }
    return .{ .units = codepoints.len, .checksum = finishSums(sums) };
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

const SimpleCase = enum { uppercase, lowercase, titlecase };

inline fn simpleCase(codepoints: []const u21, comptime operation: SimpleCase) Stats {
    var sums: [2]usize = @splat(0);
    for (codepoints) |cp| {
        const mapped = switch (operation) {
            .uppercase => uucode.get(.simple_uppercase_mapping, cp),
            .lowercase => uucode.get(.simple_lowercase_mapping, cp),
            .titlecase => uucode.get(.simple_titlecase_mapping, cp),
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

const Rational = struct { numerator: i64, denominator: u16 };

fn gcd(a_value: u64, b_value: u64) u64 {
    var a = a_value;
    var b = b_value;
    while (b != 0) {
        const next = a % b;
        a = b;
        b = next;
    }
    return a;
}

fn parseRational(bytes: []const u8) Rational {
    const slash = std.mem.indexOfScalar(u8, bytes, '/');
    var numerator = std.fmt.parseInt(i64, bytes[0 .. slash orelse bytes.len], 10) catch unreachable;
    var denominator: u16 = if (slash) |index|
        std.fmt.parseInt(u16, bytes[index + 1 ..], 10) catch unreachable
    else
        1;
    const magnitude: u64 = @intCast(if (numerator < 0) -numerator else numerator);
    const divisor = gcd(magnitude, denominator);
    numerator = @divExact(numerator, @as(i64, @intCast(divisor)));
    denominator = @intCast(@divExact(@as(u64, denominator), divisor));
    return .{ .numerator = numerator, .denominator = denominator };
}

fn numeric(cp: u21) ?struct { kind: u2, value: Rational } {
    const kind = uucode.get(.numeric_type, cp);
    return switch (kind) {
        .none => null,
        .decimal => .{ .kind = 0, .value = .{
            .numerator = uucode.get(.numeric_value_decimal, cp).?, .denominator = 1,
        } },
        .digit => .{ .kind = 1, .value = .{
            .numerator = uucode.get(.numeric_value_digit, cp).?, .denominator = 1,
        } },
        .numeric => blk: {
            const bytes = uucode.get(.numeric_value_numeric, cp);
            break :blk .{ .kind = 2, .value = parseRational(bytes) };
        },
    };
}

pub inline fn numericProperties(codepoints: []const u21) Stats {
    var sums: [4]usize = @splat(0);
    for (codepoints) |cp| {
        sums[0] +%= cp;
        if (numeric(cp)) |result| {
            sums[1] +%= result.kind + 1;
            sums[2] +%= @as(usize, @bitCast(result.value.numerator));
            sums[3] +%= result.value.denominator;
        }
    }
    return .{ .units = codepoints.len, .checksum = finishSums(sums) };
}

pub inline fn combiningClass(codepoints: []const u21) Stats {
    var sums: [2]usize = @splat(0);
    for (codepoints) |cp| {
        sums[0] +%= cp;
        sums[1] +%= uucode.get(.canonical_combining_class, cp);
    }
    return .{ .units = codepoints.len, .checksum = finishSums(sums) };
}

pub inline fn decomposition(codepoints: []const u21) Stats {
    var sums: [5]usize = @splat(0);
    for (codepoints) |cp| {
        sums[0] +%= cp;
        const kind = uucode.get(.decomposition_type, cp);
        if (kind != .default) {
            var identity: [1]u21 = undefined;
            const mapping = uucode.get(.decomposition_mapping, cp).with(&identity, cp);
            sums[1] +%= 1;
            sums[2] +%= @intFromEnum(kind) - 1;
            sums[3] +%= mapping.len;
            for (mapping) |mapped| sums[4] +%= mapped;
        }
    }
    return .{ .units = codepoints.len, .checksum = finishSums(sums) };
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
        try out.print("{d}:{d}:{d}:{d}:{d}:{d}:{d}:{d}:{d}:{d},", .{
            it.i,
            @intFromEnum(props.east_asian_width),
            @intFromBool(props.is_emoji_presentation),
            @intFromBool(props.is_emoji_vs_base),
            @intFromBool(props.is_emoji),
            @intFromBool(props.is_emoji_component),
            @intFromBool(props.is_emoji_modifier_base),
            props.wcwidth_standalone,
            @intFromBool(props.wcwidth_zero_in_grapheme),
            @intFromBool(props.is_emoji_modifier),
        });
    }
}

pub fn dumpTerminalLookup(out: *std.Io.Writer, codepoints: []const u21) !void {
    for (codepoints) |cp| {
        const props = uucode.getAll("0", cp);
        try out.print("{x}:{d}:{d}:{d}:{d}:{d}:{d}:{d}:{d}:{d},", .{
            cp,
            @intFromEnum(props.east_asian_width),
            @intFromBool(props.is_emoji_presentation),
            @intFromBool(props.is_emoji_vs_base),
            @intFromBool(props.is_emoji_modifier),
            @intFromBool(props.is_emoji_modifier_base),
            props.wcwidth_standalone,
            @intFromBool(props.wcwidth_zero_in_grapheme),
            @intFromBool(props.is_emoji),
            @intFromBool(props.is_emoji_component),
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

fn dumpSimpleCase(out: *std.Io.Writer, codepoints: []const u21, comptime operation: SimpleCase) !void {
    for (codepoints) |cp| {
        const mapped = switch (operation) {
            .uppercase => uucode.get(.simple_uppercase_mapping, cp),
            .lowercase => uucode.get(.simple_lowercase_mapping, cp),
            .titlecase => uucode.get(.simple_titlecase_mapping, cp),
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
        if (numeric(cp)) |result| {
            try out.print("{x}:{d}:{d}:{d},", .{
                cp, result.kind, result.value.numerator, result.value.denominator,
            });
        } else try out.print("{x}:n,", .{cp});
    }
}

pub fn dumpCombiningClass(out: *std.Io.Writer, codepoints: []const u21) !void {
    for (codepoints) |cp|
        try out.print("{x}:{d},", .{ cp, uucode.get(.canonical_combining_class, cp) });
}

pub fn dumpDecomposition(out: *std.Io.Writer, codepoints: []const u21) !void {
    for (codepoints) |cp| {
        const kind = uucode.get(.decomposition_type, cp);
        if (kind != .default) {
            var identity: [1]u21 = undefined;
            const mapping = uucode.get(.decomposition_mapping, cp).with(&identity, cp);
            try out.print("{x}:{d}:", .{ cp, @intFromEnum(kind) - 1 });
            for (mapping) |mapped| try out.print("{x}.", .{mapped});
            try out.writeByte(',');
        } else try out.print("{x}:n,", .{cp});
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
