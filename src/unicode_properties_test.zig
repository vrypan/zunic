const std = @import("std");
const zunic = @import("zunic");

test "terminal property representatives" {
    try std.testing.expectEqual(zunic.EastAsianWidth.narrow, zunic.eastAsianWidth('A'));
    try std.testing.expectEqual(zunic.EastAsianWidth.wide, zunic.eastAsianWidth(0x4e00));
    try std.testing.expectEqual(zunic.EastAsianWidth.fullwidth, zunic.eastAsianWidth(0xff01));
    try std.testing.expectEqual(zunic.EastAsianWidth.halfwidth, zunic.eastAsianWidth(0xff61));
    try std.testing.expect(zunic.isEmojiPresentation(0x1f600));
    try std.testing.expect(!zunic.isEmojiPresentation('A'));
    try std.testing.expect(zunic.isEmojiVariationBase(0x231b));
    try std.testing.expect(!zunic.isEmojiVariationBase(0x1f46c));
    try std.testing.expect(zunic.isEmojiModifier(0x1f3fb));
    try std.testing.expect(zunic.isEmojiModifierBase(0x1f44d));
}

test "uucode-derived width facts stay separate" {
    try std.testing.expectEqual(@as(u2, 0), zunic.widthProperties(0x0000).standalone);
    try std.testing.expectEqual(@as(u2, 1), zunic.widthProperties(0x00ad).standalone);
    try std.testing.expectEqual(@as(u2, 1), zunic.widthProperties(0x0600).standalone);
    try std.testing.expect(zunic.widthProperties(0x0600).zero_in_grapheme);
    try std.testing.expect(zunic.widthProperties(0x1161).zero_in_grapheme);
    try std.testing.expect(zunic.widthProperties(0x1f3fb).zero_in_grapheme);
    try std.testing.expectEqual(@as(u2, 3), zunic.widthProperties(0x2e3b).standalone);
    try std.testing.expectEqual(@as(u2, 2), zunic.widthProperties(0x20e3).standalone);
    try std.testing.expect(zunic.widthProperties(0x20e3).zero_in_grapheme);
    try std.testing.expectEqual(@as(u2, 0), zunic.widthProperties(0xfe0e).standalone);
    try std.testing.expectEqual(@as(u2, 0), zunic.widthProperties(0xfe0f).standalone);
}

test "surrogate and wider u21 policies are explicit" {
    try std.testing.expectEqual(@as(u2, 0), zunic.widthProperties(0xd800).standalone);
    try std.testing.expectEqual(zunic.EastAsianWidth.ambiguous, zunic.eastAsianWidth(0xe000));
    try std.testing.expectEqual(@as(u2, 1), zunic.widthProperties(0xe000).standalone);
    try std.testing.expectEqual(zunic.EastAsianWidth.neutral, zunic.eastAsianWidth(0x0378));
    try std.testing.expectEqual(@as(u2, 1), zunic.widthProperties(0x0378).standalone);
    const outside: u21 = 0x110000;
    try std.testing.expectEqual(zunic.EastAsianWidth.neutral, zunic.eastAsianWidth(outside));
    try std.testing.expect(!zunic.isEmojiPresentation(outside));
    try std.testing.expect(!zunic.isEmojiVariationBase(outside));
    const terminal = zunic.terminalProperties(outside);
    try std.testing.expectEqual(zunic.EastAsianWidth.neutral, terminal.east_asian_width);
    try std.testing.expect(!terminal.emoji_presentation);
    try std.testing.expect(!terminal.emoji_variation_base);
    try std.testing.expect(!terminal.emoji_modifier);
    try std.testing.expect(!terminal.emoji_modifier_base);
    try std.testing.expectEqual(@as(u2, 1), terminal.standalone);
    try std.testing.expect(terminal.zero_in_grapheme);
    const width = zunic.widthProperties(outside);
    try std.testing.expectEqual(@as(u2, 1), width.standalone);
    try std.testing.expect(width.zero_in_grapheme);
    try std.testing.expect(!width.emoji_modifier);
}

test "fused terminal records preserve public property invariants" {
    var raw: u32 = 0;
    while (raw <= zunic.max_codepoint) : (raw += 1) {
        const cp: u21 = @intCast(raw);
        const terminal = zunic.terminalProperties(cp);
        const eaw = terminal.east_asian_width;
        const width = zunic.widthProperties(cp);
        try std.testing.expectEqual(eaw, zunic.eastAsianWidth(cp));
        try std.testing.expectEqual(terminal.emoji_presentation, zunic.isEmojiPresentation(cp));
        try std.testing.expectEqual(terminal.emoji_variation_base, zunic.isEmojiVariationBase(cp));
        try std.testing.expectEqual(terminal.emoji_modifier, zunic.isEmojiModifier(cp));
        try std.testing.expectEqual(terminal.emoji_modifier_base, zunic.isEmojiModifierBase(cp));
        try std.testing.expectEqual(terminal.standalone, width.standalone);
        try std.testing.expectEqual(terminal.zero_in_grapheme, width.zero_in_grapheme);
        try std.testing.expectEqual(terminal.emoji_modifier, width.emoji_modifier);
        try std.testing.expectEqual(
            eaw == .wide or eaw == .fullwidth or eaw == .halfwidth,
            zunic.isEastAsianWide(cp),
        );
    }
}
