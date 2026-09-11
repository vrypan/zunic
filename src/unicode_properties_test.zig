const std = @import("std");
const zunic = @import("zunic");

test "terminal property representatives" {
    try std.testing.expectEqual(zunic.EastAsianWidth.narrow, zunic.cp('A').terminal().eastAsianWidth);
    try std.testing.expectEqual(zunic.EastAsianWidth.wide, zunic.cp(0x4e00).terminal().eastAsianWidth);
    try std.testing.expectEqual(zunic.EastAsianWidth.fullwidth, zunic.cp(0xff01).terminal().eastAsianWidth);
    try std.testing.expectEqual(zunic.EastAsianWidth.halfwidth, zunic.cp(0xff61).terminal().eastAsianWidth);
    try std.testing.expect(zunic.cp(0x1f600).terminal().isEmojiPresentation);
    try std.testing.expect(!zunic.cp('A').terminal().isEmojiPresentation);
    try std.testing.expect(zunic.cp(0x231b).terminal().isEmojiVariationBase);
    try std.testing.expect(!zunic.cp(0x1f46c).terminal().isEmojiVariationBase);
    try std.testing.expect(zunic.cp(0x1f3fb).terminal().isEmojiModifier);
    try std.testing.expect(zunic.cp(0x1f44d).terminal().isEmojiModifierBase);
}

test "uucode-derived width facts stay separate" {
    try std.testing.expectEqual(@as(u2, 0), zunic.cp(0x0000).terminal().standalone);
    try std.testing.expectEqual(@as(u2, 1), zunic.cp(0x00ad).terminal().standalone);
    try std.testing.expectEqual(@as(u2, 1), zunic.cp(0x0600).terminal().standalone);
    try std.testing.expect(zunic.cp(0x0600).terminal().zeroInGrapheme);
    try std.testing.expect(zunic.cp(0x1161).terminal().zeroInGrapheme);
    try std.testing.expect(zunic.cp(0x1f3fb).terminal().zeroInGrapheme);
    try std.testing.expectEqual(@as(u2, 3), zunic.cp(0x2e3b).terminal().standalone);
    try std.testing.expectEqual(@as(u2, 2), zunic.cp(0x20e3).terminal().standalone);
    try std.testing.expect(zunic.cp(0x20e3).terminal().zeroInGrapheme);
    try std.testing.expectEqual(@as(u2, 0), zunic.cp(0xfe0e).terminal().standalone);
    try std.testing.expectEqual(@as(u2, 0), zunic.cp(0xfe0f).terminal().standalone);
}

test "surrogate and wider u21 policies are explicit" {
    try std.testing.expectEqual(@as(u2, 0), zunic.cp(0xd800).terminal().standalone);
    try std.testing.expectEqual(zunic.EastAsianWidth.ambiguous, zunic.cp(0xe000).terminal().eastAsianWidth);
    try std.testing.expectEqual(@as(u2, 1), zunic.cp(0xe000).terminal().standalone);
    try std.testing.expectEqual(zunic.EastAsianWidth.neutral, zunic.cp(0x0378).terminal().eastAsianWidth);
    try std.testing.expectEqual(@as(u2, 1), zunic.cp(0x0378).terminal().standalone);
    const outside: u21 = 0x110000;
    try std.testing.expectEqual(zunic.EastAsianWidth.neutral, zunic.cp(outside).terminal().eastAsianWidth);
    try std.testing.expect(!zunic.cp(outside).terminal().isEmojiPresentation);
    try std.testing.expect(!zunic.cp(outside).terminal().isEmojiVariationBase);
    const terminal = zunic.cp(outside).terminal();
    try std.testing.expectEqual(zunic.EastAsianWidth.neutral, terminal.eastAsianWidth);
    try std.testing.expect(!terminal.isEmojiPresentation);
    try std.testing.expect(!terminal.isEmojiVariationBase);
    try std.testing.expect(!terminal.isEmojiModifier);
    try std.testing.expect(!terminal.isEmojiModifierBase);
    try std.testing.expectEqual(@as(u2, 1), terminal.standalone);
    try std.testing.expect(terminal.zeroInGrapheme);
}
