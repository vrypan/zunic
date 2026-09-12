const std = @import("std");
const codepoints = @import("cp");

test "terminal property representatives" {
    try std.testing.expectEqual(@FieldType(codepoints.TerminalProperties, "eastAsianWidth").narrow, codepoints.init('A').terminal().eastAsianWidth);
    try std.testing.expectEqual(@FieldType(codepoints.TerminalProperties, "eastAsianWidth").wide, codepoints.init(0x4e00).terminal().eastAsianWidth);
    try std.testing.expectEqual(@FieldType(codepoints.TerminalProperties, "eastAsianWidth").fullwidth, codepoints.init(0xff01).terminal().eastAsianWidth);
    try std.testing.expectEqual(@FieldType(codepoints.TerminalProperties, "eastAsianWidth").halfwidth, codepoints.init(0xff61).terminal().eastAsianWidth);
    try std.testing.expect(codepoints.init(0x1f600).terminal().isEmojiPresentation);
    try std.testing.expect(!codepoints.init('A').terminal().isEmojiPresentation);
    try std.testing.expect(codepoints.init(0x231b).terminal().isEmojiVariationBase);
    try std.testing.expect(!codepoints.init(0x1f46c).terminal().isEmojiVariationBase);
    try std.testing.expect(codepoints.init(0x1f3fb).terminal().isEmojiModifier);
    try std.testing.expect(codepoints.init(0x1f44d).terminal().isEmojiModifierBase);
}

test "uucode-derived width facts stay separate" {
    try std.testing.expectEqual(@as(u2, 0), codepoints.init(0x0000).terminal().standalone);
    try std.testing.expectEqual(@as(u2, 1), codepoints.init(0x00ad).terminal().standalone);
    try std.testing.expectEqual(@as(u2, 1), codepoints.init(0x0600).terminal().standalone);
    try std.testing.expect(codepoints.init(0x0600).terminal().zeroInGrapheme);
    try std.testing.expect(codepoints.init(0x1161).terminal().zeroInGrapheme);
    try std.testing.expect(codepoints.init(0x1f3fb).terminal().zeroInGrapheme);
    try std.testing.expectEqual(@as(u2, 3), codepoints.init(0x2e3b).terminal().standalone);
    try std.testing.expectEqual(@as(u2, 2), codepoints.init(0x20e3).terminal().standalone);
    try std.testing.expect(codepoints.init(0x20e3).terminal().zeroInGrapheme);
    try std.testing.expectEqual(@as(u2, 0), codepoints.init(0xfe0e).terminal().standalone);
    try std.testing.expectEqual(@as(u2, 0), codepoints.init(0xfe0f).terminal().standalone);
}

test "surrogate and wider u21 policies are explicit" {
    try std.testing.expectEqual(@as(u2, 0), codepoints.init(0xd800).terminal().standalone);
    try std.testing.expectEqual(@FieldType(codepoints.TerminalProperties, "eastAsianWidth").ambiguous, codepoints.init(0xe000).terminal().eastAsianWidth);
    try std.testing.expectEqual(@as(u2, 1), codepoints.init(0xe000).terminal().standalone);
    try std.testing.expectEqual(@FieldType(codepoints.TerminalProperties, "eastAsianWidth").neutral, codepoints.init(0x0378).terminal().eastAsianWidth);
    try std.testing.expectEqual(@as(u2, 1), codepoints.init(0x0378).terminal().standalone);
    const outside: u21 = 0x110000;
    try std.testing.expectEqual(@FieldType(codepoints.TerminalProperties, "eastAsianWidth").neutral, codepoints.init(outside).terminal().eastAsianWidth);
    try std.testing.expect(!codepoints.init(outside).terminal().isEmojiPresentation);
    try std.testing.expect(!codepoints.init(outside).terminal().isEmojiVariationBase);
    const terminal = codepoints.init(outside).terminal();
    try std.testing.expectEqual(@FieldType(codepoints.TerminalProperties, "eastAsianWidth").neutral, terminal.eastAsianWidth);
    try std.testing.expect(!terminal.isEmojiPresentation);
    try std.testing.expect(!terminal.isEmojiVariationBase);
    try std.testing.expect(!terminal.isEmojiModifier);
    try std.testing.expect(!terminal.isEmojiModifierBase);
    try std.testing.expectEqual(@as(u2, 1), terminal.standalone);
    try std.testing.expect(terminal.zeroInGrapheme);
}
