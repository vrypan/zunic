const std = @import("std");
const zunic = @import("zunic");

var first_input: u21 = 0x1f600;
var second_input: u21 = 0x0301;

inline fn mix(hash: *u64, value: anytype) void {
    hash.* = (hash.* ^ @as(u64, @intCast(value))) *% 0x100000001b3;
}

fn isGhosttySymbol(value: u21, category: zunic.GeneralCategory) bool {
    if (category == .co) return true;
    return switch (value) {
        0x2190...0x21ff,
        0x2460...0x24ff,
        0x2600...0x26ff,
        0x2700...0x27bf,
        0x1f100...0x1f1ff,
        0x1f300...0x1f6ff,
        => true,
        else => false,
    };
}

fn useGhosttyCoverage(first: u21, second: u21) u64 {
    var hash: u64 = 0xcbf29ce484222325;
    const codepoint = zunic.cp(first);
    const general = codepoint.general();
    const terminal = codepoint.terminal();
    const grapheme = codepoint.grapheme();

    mix(&hash, @intFromEnum(general.category));
    mix(&hash, @intFromEnum(terminal.eastAsianWidth));
    mix(&hash, @intFromBool(terminal.isEmojiPresentation));
    mix(&hash, @intFromBool(terminal.isEmojiVariationBase));
    mix(&hash, @intFromBool(terminal.isEmojiModifier));
    mix(&hash, @intFromBool(terminal.isEmojiModifierBase));
    mix(&hash, terminal.standalone);
    mix(&hash, @intFromBool(terminal.zeroInGrapheme));
    mix(&hash, @intFromEnum(grapheme.gcb));
    mix(&hash, @intFromEnum(grapheme.incb));
    mix(&hash, @intFromBool(grapheme.extendedPictographic));

    const width: u2 = if (first > zunic.max_codepoint)
        1
    else if (terminal.zeroInGrapheme and !terminal.isEmojiModifier and grapheme.gcb != .prepend)
        0
    else
        @min(2, terminal.standalone);
    mix(&hash, width);
    mix(&hash, @intFromBool(isGhosttySymbol(first, general.category)));

    var folded = codepoint.fullCaseFold();
    mix(&hash, folded.len);
    for (folded.slice()) |value| mix(&hash, value);

    var state: zunic.GraphemeState = .{};
    mix(&hash, @intFromBool(zunic.graphemeBreak(first, second, &state)));
    return hash;
}

pub fn main() void {
    const first: *volatile u21 = &first_input;
    const second: *volatile u21 = &second_input;
    std.mem.doNotOptimizeAway(useGhosttyCoverage(first.*, second.*));
}
