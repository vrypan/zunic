const std = @import("std");
const codepoints = @import("cp");

test "ASCII arrays agree with the fused record" {
    // The trie is verified exhaustively against the pinned UCD by
    // src/tools/test-properties.py. What that cannot see is decoded_token.at's ASCII
    // shortcut, which reads two separate arrays and hard-codes one column.
    const properties = @import("tables").properties;
    var cp: u7 = 0;
    while (true) {
        const r = properties.record(cp);
        try std.testing.expectEqual(properties.grapheme_ascii[cp], properties.graphemeOf(r));
        try std.testing.expectEqual(properties.line_break_ascii[cp], r.line_break);
        try std.testing.expectEqual(@as(u2, 1), r.width);
        if (cp == 127) break;
        cp += 1;
    }
}

test "code-point width and East Asian wide answer different questions" {
    // U+302A IDEOGRAPHIC LEVEL TONE MARK: Mn, and East_Asian_Width=Wide.
    // Category forces width to zero regardless of east_asian_wide.
    try std.testing.expect(codepoints.init(0x302A).isEastAsianWide());
    try std.testing.expectEqual(@as(u2, 0), codepoints.init(0x302A).width());

    // U+FF61 HALFWIDTH IDEOGRAPHIC FULL STOP: East_Asian_Width=Halfwidth.
    // east_asian_wide is true (it covers H too), but width only treats
    // Wide/Fullwidth as two columns, so this measures one.
    try std.testing.expect(codepoints.init(0xFF61).isEastAsianWide());
    try std.testing.expectEqual(@as(u2, 1), codepoints.init(0xFF61).width());

    // An ordinary CJK ideograph agrees on both questions.
    try std.testing.expect(codepoints.init(0x4E00).isEastAsianWide());
    try std.testing.expectEqual(@as(u2, 2), codepoints.init(0x4E00).width());

    try std.testing.expect(!codepoints.init('a').isEastAsianWide());
    try std.testing.expectEqual(@as(u2, 1), codepoints.init('a').width());
}

test "general group agrees with the pinned UCD" {
    const Want = struct {
        cp: u21,
        category: @import("tables").general_category.GeneralCategory,
        alphabetic: bool,
        lowercase: bool,
        uppercase: bool,
        cased: bool,
        case_ignorable: bool,
        math: bool,
        id_start: bool,
        id_continue: bool,
        xid_start: bool,
        xid_continue: bool,
        default_ignorable: bool,
        grapheme_base: bool,
        grapheme_extend: bool,
    };
    // Every row transcribed directly from UnicodeData-17.0.0.txt and
    // DerivedCoreProperties-17.0.0.txt, not from general Unicode knowledge:
    // several of these (Uppercase excluding Lt, Math spanning far more than
    // Sm) are easy to get wrong by assumption.
    const cases = [_]Want{
        // 'A': Lu, cased and identifier-capable both ways.
        .{ .cp = 'A', .category = .lu, .alphabetic = true, .lowercase = false, .uppercase = true, .cased = true, .case_ignorable = false, .math = false, .id_start = true, .id_continue = true, .xid_start = true, .xid_continue = true, .default_ignorable = false, .grapheme_base = true, .grapheme_extend = false },
        // 'a': Ll, the Lowercase counterpart.
        .{ .cp = 'a', .category = .ll, .alphabetic = true, .lowercase = true, .uppercase = false, .cased = true, .case_ignorable = false, .math = false, .id_start = true, .id_continue = true, .xid_start = true, .xid_continue = true, .default_ignorable = false, .grapheme_base = true, .grapheme_extend = false },
        // '0': Nd. ID_Continue but not ID_Start -- a digit cannot begin an
        // identifier under Unicode's default lexical rules.
        .{ .cp = '0', .category = .nd, .alphabetic = false, .lowercase = false, .uppercase = false, .cased = false, .case_ignorable = false, .math = false, .id_start = false, .id_continue = true, .xid_start = false, .xid_continue = true, .default_ignorable = false, .grapheme_base = true, .grapheme_extend = false },
        // '+': Sm, and Math -- but not every Math code point is Sm; see
        // isMath's doc comment for the categories that also carry it.
        .{ .cp = '+', .category = .sm, .alphabetic = false, .lowercase = false, .uppercase = false, .cased = false, .case_ignorable = false, .math = true, .id_start = false, .id_continue = false, .xid_start = false, .xid_continue = false, .default_ignorable = false, .grapheme_base = true, .grapheme_extend = false },
        // U+0020 SPACE: Zs, no derived boolean here is true.
        .{ .cp = 0x0020, .category = .zs, .alphabetic = false, .lowercase = false, .uppercase = false, .cased = false, .case_ignorable = false, .math = false, .id_start = false, .id_continue = false, .xid_start = false, .xid_continue = false, .default_ignorable = false, .grapheme_base = true, .grapheme_extend = false },
        // U+0301 COMBINING ACUTE ACCENT: Mn, Case_Ignorable and
        // Grapheme_Extend, not Grapheme_Base -- the opposite shape from the
        // letters above.
        .{ .cp = 0x0301, .category = .mn, .alphabetic = false, .lowercase = false, .uppercase = false, .cased = false, .case_ignorable = true, .math = false, .id_start = false, .id_continue = true, .xid_start = false, .xid_continue = true, .default_ignorable = false, .grapheme_base = false, .grapheme_extend = true },
        // U+00AD SOFT HYPHEN: Cf, Default_Ignorable_Code_Point.
        .{ .cp = 0x00AD, .category = .cf, .alphabetic = false, .lowercase = false, .uppercase = false, .cased = false, .case_ignorable = true, .math = false, .id_start = false, .id_continue = false, .xid_start = false, .xid_continue = false, .default_ignorable = true, .grapheme_base = false, .grapheme_extend = false },
        // U+0378: unassigned in Unicode 17.0.0, so Cn and every boolean false.
        .{ .cp = 0x0378, .category = .cn, .alphabetic = false, .lowercase = false, .uppercase = false, .cased = false, .case_ignorable = false, .math = false, .id_start = false, .id_continue = false, .xid_start = false, .xid_continue = false, .default_ignorable = false, .grapheme_base = false, .grapheme_extend = false },
    };
    for (cases) |want| {
        const props = codepoints.init(want.cp).general();
        try std.testing.expectEqual(want.category, props.category);
        try std.testing.expectEqual(want.alphabetic, props.isAlphabetic);
        try std.testing.expectEqual(want.lowercase, props.isLowercase);
        try std.testing.expectEqual(want.uppercase, props.isUppercase);
        try std.testing.expectEqual(want.cased, props.isCased);
        try std.testing.expectEqual(want.case_ignorable, props.isCaseIgnorable);
        try std.testing.expectEqual(want.math, props.isMath);
        try std.testing.expectEqual(want.id_start, props.isIdStart);
        try std.testing.expectEqual(want.id_continue, props.isIdContinue);
        try std.testing.expectEqual(want.xid_start, props.isXidStart);
        try std.testing.expectEqual(want.xid_continue, props.isXidContinue);
        try std.testing.expectEqual(want.default_ignorable, props.isDefaultIgnorable);
        try std.testing.expectEqual(want.grapheme_base, props.isGraphemeBase);
        try std.testing.expectEqual(want.grapheme_extend, props.isGraphemeExtend);
    }

    // Every Lu/Ll/Lt code point is Cased, by the property's own definition
    // (verified exhaustively by src/tools/test-general-category.py; this is
    // a second, narrower consistency signal from inside the test suite).
    try std.testing.expect(codepoints.init('A').general().isCased);
    try std.testing.expect(codepoints.init('A').general().category == .lu);
}

test "code-point groups preserve table facts across the complete u21 domain" {
    const tables = @import("tables");
    var raw: u32 = 0;
    while (raw <= std.math.maxInt(u21)) : (raw += 1) {
        const value: u21 = @intCast(raw);
        const point = codepoints.init(value);
        try std.testing.expectEqual(value, point.value);
        const general = point.general();
        const expected_general = tables.general_category.generalCategoryProperties(value);
        try std.testing.expectEqual(expected_general.category, general.category);
        try std.testing.expectEqual(expected_general.is_alphabetic, general.isAlphabetic);
        try std.testing.expectEqual(expected_general.is_lowercase, general.isLowercase);
        try std.testing.expectEqual(expected_general.is_uppercase, general.isUppercase);
        try std.testing.expectEqual(expected_general.is_cased, general.isCased);
        try std.testing.expectEqual(expected_general.is_case_ignorable, general.isCaseIgnorable);
        try std.testing.expectEqual(expected_general.is_math, general.isMath);
        try std.testing.expectEqual(expected_general.is_id_start, general.isIdStart);
        try std.testing.expectEqual(expected_general.is_id_continue, general.isIdContinue);
        try std.testing.expectEqual(expected_general.is_xid_start, general.isXidStart);
        try std.testing.expectEqual(expected_general.is_xid_continue, general.isXidContinue);
        try std.testing.expectEqual(expected_general.is_default_ignorable, general.isDefaultIgnorable);
        try std.testing.expectEqual(expected_general.is_grapheme_base, general.isGraphemeBase);
        try std.testing.expectEqual(expected_general.is_grapheme_extend, general.isGraphemeExtend);
        try std.testing.expectEqual(expected_general._padding, general._padding);
        const terminal = point.terminal();
        const expected_terminal = tables.terminal_properties.terminalProperties(value);
        try std.testing.expectEqual(expected_terminal.east_asian_width, terminal.eastAsianWidth);
        try std.testing.expectEqual(expected_terminal.emoji_presentation, terminal.isEmojiPresentation);
        try std.testing.expectEqual(expected_terminal.emoji_variation_base, terminal.isEmojiVariationBase);
        try std.testing.expectEqual(expected_terminal.emoji_modifier, terminal.isEmojiModifier);
        try std.testing.expectEqual(expected_terminal.emoji_modifier_base, terminal.isEmojiModifierBase);
        try std.testing.expectEqual(expected_terminal.standalone, terminal.standalone);
        try std.testing.expectEqual(expected_terminal.zero_in_grapheme, terminal.zeroInGrapheme);
        try std.testing.expectEqual(expected_terminal.emoji, terminal.isEmoji);
        try std.testing.expectEqual(expected_terminal.emoji_component, terminal.isEmojiComponent);
        const grapheme = point.grapheme();
        const expected_grapheme = tables.properties.graphemeProperties(value);
        try std.testing.expectEqual(expected_grapheme.gcb, grapheme.gcb);
        try std.testing.expectEqual(expected_grapheme.incb, grapheme.incb);
        try std.testing.expectEqual(expected_grapheme.extended_pictographic, grapheme.extendedPictographic);
        try std.testing.expectEqual(tables.properties.codepointWidth(value), point.width());
        try std.testing.expectEqual(tables.properties.isEastAsianWide(value), point.isEastAsianWide());
    }
}
