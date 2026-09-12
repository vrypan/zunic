const std = @import("std");
const uucode = @import("uucode");

var first_input: u21 = 0x1f600;
var second_input: u21 = 0x0301;

inline fn mix(hash: *u64, value: anytype) void {
    hash.* = (hash.* ^ @as(u64, @intCast(value))) *% 0x100000001b3;
}

fn isGhosttySymbol(value: u21, category: uucode.types.GeneralCategory) bool {
    if (category == .other_private_use) return true;
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
    const category = uucode.get(.general_category, first);
    const eaw = uucode.get(.east_asian_width, first);
    const presentation = uucode.get(.is_emoji_presentation, first);
    const variation_base = uucode.get(.is_emoji_vs_base, first);
    const modifier = uucode.get(.is_emoji_modifier, first);
    const modifier_base = uucode.get(.is_emoji_modifier_base, first);
    const standalone = uucode.get(.wcwidth_standalone, first);
    const zero = uucode.get(.wcwidth_zero_in_grapheme, first);
    const gcb = uucode.get(.grapheme_break, first);
    const gcb_no_control = uucode.get(.grapheme_break_no_control, first);

    mix(&hash, @intFromEnum(category));
    mix(&hash, @intFromEnum(eaw));
    mix(&hash, @intFromBool(presentation));
    mix(&hash, @intFromBool(variation_base));
    mix(&hash, @intFromBool(modifier));
    mix(&hash, @intFromBool(modifier_base));
    mix(&hash, standalone);
    mix(&hash, @intFromBool(zero));
    mix(&hash, @intFromEnum(gcb));
    mix(&hash, @intFromEnum(gcb_no_control));

    const width: u2 = if (zero and !modifier and gcb_no_control != .prepend)
        0
    else
        @min(2, standalone);
    mix(&hash, width);
    mix(&hash, @intFromBool(isGhosttySymbol(first, category)));

    var identity: [1]u21 = undefined;
    const folded = uucode.get(.case_folding_full, first).with(&identity, first);
    mix(&hash, folded.len);
    for (folded) |value| mix(&hash, value);

    var state: uucode.grapheme.BreakState = .default;
    mix(&hash, @intFromBool(uucode.grapheme.computeGraphemeBreak(
        gcb,
        uucode.get(.grapheme_break, second),
        &state,
    )));
    return hash;
}

pub fn main() void {
    const first: *volatile u21 = &first_input;
    const second: *volatile u21 = &second_input;
    std.mem.doNotOptimizeAway(useGhosttyCoverage(first.*, second.*));
}
