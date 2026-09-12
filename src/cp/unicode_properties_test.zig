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
    try std.testing.expect(codepoints.init('#').terminal().isEmoji);
    try std.testing.expect(!codepoints.init('A').terminal().isEmoji);
    try std.testing.expect(codepoints.init(0x200d).terminal().isEmojiComponent);
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
    try std.testing.expect(!terminal.isEmoji);
    try std.testing.expect(!terminal.isEmojiComponent);
    try std.testing.expectEqual(@as(u2, 1), terminal.standalone);
    try std.testing.expect(terminal.zeroInGrapheme);
}

test "numeric values are exact and preserve their Unicode kind" {
    const decimal = codepoints.init('5').numeric().?;
    try std.testing.expectEqual(codepoints.NumericType.decimal, decimal.kind);
    try std.testing.expectEqual(@as(i64, 5), decimal.numerator);
    try std.testing.expectEqual(@as(u16, 1), decimal.denominator);

    const digit = codepoints.init(0x00b2).numeric().?; // SUPERSCRIPT TWO
    try std.testing.expectEqual(codepoints.NumericType.digit, digit.kind);
    try std.testing.expectEqual(@as(i64, 2), digit.numerator);

    const fraction = codepoints.init(0x2153).numeric().?; // VULGAR FRACTION ONE THIRD
    try std.testing.expectEqual(codepoints.NumericType.numeric, fraction.kind);
    try std.testing.expectEqual(@as(i64, 1), fraction.numerator);
    try std.testing.expectEqual(@as(u16, 3), fraction.denominator);

    const negative = codepoints.init(0x0f33).numeric().?;
    try std.testing.expectEqual(@as(i64, -1), negative.numerator);
    try std.testing.expectEqual(@as(u16, 2), negative.denominator);
    try std.testing.expect(codepoints.init('A').numeric() == null);
    try std.testing.expect(codepoints.init(0x110000).numeric() == null);
}

test "normalization facts expose immediate mappings" {
    try std.testing.expectEqual(@as(u8, 230), codepoints.init(0x0301).canonicalCombiningClass());
    try std.testing.expectEqual(@as(u8, 0), codepoints.init('A').canonicalCombiningClass());
    for ([_]u21{ 0, 127, 128, 0xd800, 0x2ffff, 0x30000, 0x10ffff, 0x110000, 0x1fffff }) |value| {
        try std.testing.expectEqual(@as(u8, 0), codepoints.init(value).canonicalCombiningClass());
    }

    const canonical = codepoints.init(0x00e9).decomposition().?;
    try std.testing.expectEqual(codepoints.DecompositionType.canonical, canonical.type);
    try std.testing.expectEqualSlices(u21, &.{ 'e', 0x0301 }, canonical.mapping);
    try std.testing.expect(!canonical.fullCompositionExclusion);

    const excluded = codepoints.init(0x0344).decomposition().?;
    try std.testing.expect(excluded.fullCompositionExclusion);

    const no_break = codepoints.init(0x00a0).decomposition().?;
    try std.testing.expectEqual(codepoints.DecompositionType.no_break, no_break.type);
    try std.testing.expectEqualSlices(u21, &.{0x20}, no_break.mapping);

    const ligature = codepoints.init(0xfb01).decomposition().?;
    try std.testing.expectEqual(codepoints.DecompositionType.compat, ligature.type);
    try std.testing.expectEqualSlices(u21, &.{ 'f', 'i' }, ligature.mapping);
    try std.testing.expect(codepoints.init('A').decomposition() == null);
    try std.testing.expect(codepoints.init(0x110000).decomposition() == null);
}
