const std = @import("std");
const unicode = @import("zunic");

test "unicode component compiles as an independent root" {
    const step = unicode.utf8.step("x");
    try std.testing.expectEqual(@as(usize, 1), step.len);
    try std.testing.expectEqual(@as(usize, 2), unicode.text("🇬🇷").width());
}

test "text validation checks the complete byte slice" {
    try unicode.text("").validate();
    try unicode.text("Hello, 世界 👩‍👩‍👧‍👦").validate();
    try unicode.text("\u{fffd}").validate();

    const invalid = [_][]const u8{
        "\xff", // stray byte
        "\xc0\x80", // overlong encoding
        "\xed\xa0\x80", // surrogate
        "\xf4\x90\x80\x80", // above U+10FFFF
        "\xe2\x82", // truncated sequence
        "valid prefix\xe2xvalid suffix", // broken continuation
    };
    for (invalid) |bytes| {
        try std.testing.expectError(error.InvalidUtf8, unicode.text(bytes).validate());
    }
}

test "grapheme traversal retains byte spans and optional terminal measure" {
    const text = "e\xcc\x81界👩‍👩‍👧‍👦\x00";
    var it = unicode.text(text).graphemes().measured().iterator();
    while (it.next()) |span| {
        const measured = @import("layout").width.measureCluster(text[span.start.value..span.end.value]);
        try std.testing.expectEqual(measured.columns, span.columns);
        try std.testing.expectEqual(measured.renderable, span.renderable);
    }
}

test "GB11 permits Extend before one ZWJ but not repeated ZWJs" {
    const emoji = "\u{1F600}";
    for ([_][]const u8{ emoji ++ "\u{200D}\u{200D}", emoji ++ "\u{200D}\u{0301}\u{200D}" }) |prefix| {
        var buffer: [32]u8 = undefined;
        @memcpy(buffer[0..prefix.len], prefix);
        @memcpy(buffer[prefix.len..][0..emoji.len], emoji);
        const bytes = buffer[0 .. prefix.len + emoji.len];
        var it = unicode.text(bytes).graphemes().measured().iterator();
        for ([_][2]usize{ .{ 0, prefix.len }, .{ prefix.len, bytes.len } }) |expected| {
            const span = it.next() orelse return error.TestUnexpectedResult;
            try std.testing.expectEqual(expected[0], span.start.value);
            try std.testing.expectEqual(expected[1], span.end.value);
            try std.testing.expectEqual(@as(u2, 2), span.columns);
        }
        try std.testing.expect(it.next() == null);
        try std.testing.expectEqual(@as(usize, 4), unicode.text(bytes).width());
        var lines = (try unicode.text(bytes).wrap(.{ .max_columns = 2 })).iterator();
        try std.testing.expectEqual(prefix.len, lines.next().?.end.value);
        try std.testing.expectEqual(bytes.len, lines.next().?.end.value);
        try std.testing.expect(lines.next() == null);
    }
    // Legitimate Extend* ZWJ sequences must remain a single cluster.
    const valid = emoji ++ "\u{0301}\u{200D}" ++ emoji;
    var it = unicode.text(valid).graphemes().iterator();
    try std.testing.expectEqual(valid.len, it.next().?.end.value);
    try std.testing.expect(it.next() == null);
    try std.testing.expectEqual(@as(usize, 2), unicode.text(valid).width());
}

test "measured spans carry column and renderability" {
    const text = "\xcc\x81a\u{754c}b";
    try std.testing.expectEqual(@as(usize, 4), unicode.text(text).width());

    // A leading combining mark is its own zero-column cluster; the wide
    // scalar occupies two columns. Callers sum these to locate a column,
    // which is why `columnAt`/`byteAt` are not part of the surface.
    var it = unicode.text(text).graphemes().measured().iterator();
    const first = it.next().?;
    try std.testing.expectEqual(@as(u2, 0), first.columns);
    _ = it.next();
    const wide = it.next().?;
    try std.testing.expectEqual(@as(u2, 2), wide.columns);
    try std.testing.expect(wide.renderable);
}

test "terminators report every hard break as a byte extent" {
    const cases = [_]struct { input: []const u8, spans: []const [2]usize }{
        .{ .input = "a\nb", .spans = &.{.{ 1, 2 }} },
        .{ .input = "a\x0bb", .spans = &.{.{ 1, 2 }} },
        .{ .input = "a\x0cb", .spans = &.{.{ 1, 2 }} },
        .{ .input = "a\rb", .spans = &.{.{ 1, 2 }} },
        // CRLF is one terminator of length two.
        .{ .input = "a\r\nb", .spans = &.{.{ 1, 3 }} },
        .{ .input = "a\u{0085}b", .spans = &.{.{ 1, 3 }} },
        .{ .input = "a\u{2028}b", .spans = &.{.{ 1, 4 }} },
        .{ .input = "a\u{2029}b", .spans = &.{.{ 1, 4 }} },
        // Not terminators: NBSP, and truncated lead bytes.
        .{ .input = "a\u{00a0}b", .spans = &.{} },
        .{ .input = "a\xc2", .spans = &.{} },
        .{ .input = "a\xe2\x80", .spans = &.{} },
        .{ .input = "a\xe2\x80\xa7b", .spans = &.{} },
        // Empty input, and terminators at both edges.
        .{ .input = "", .spans = &.{} },
        .{ .input = "\n", .spans = &.{.{ 0, 1 }} },
        .{ .input = "\n\n", .spans = &.{ .{ 0, 1 }, .{ 1, 2 } } },
        .{ .input = "a\n", .spans = &.{.{ 1, 2 }} },
    };
    for (cases) |case| {
        var it = unicode.text(case.input).terminators().iterator();
        for (case.spans) |want| {
            const got = it.next() orelse return error.TestUnexpectedResult;
            try std.testing.expectEqual(want[0], got.start.value);
            try std.testing.expectEqual(want[1], got.end.value);
        }
        try std.testing.expect(it.next() == null);
        try std.testing.expectEqual(case.spans.len, unicode.text(case.input).terminators().count());
    }
}

test "paragraph content derives from terminators without special cases" {
    // The recipe documented in plans/021: content is the gaps, and the single
    // `pos < len` guard is the terminator-versus-separator decision.
    const cases = [_]struct { input: []const u8, want: []const [2]usize }{
        .{ .input = "", .want = &.{} },
        .{ .input = "a", .want = &.{.{ 0, 1 }} },
        .{ .input = "a\n", .want = &.{.{ 0, 1 }} },
        .{ .input = "\n", .want = &.{.{ 0, 0 }} },
        .{ .input = "a\n\nb", .want = &.{ .{ 0, 1 }, .{ 2, 2 }, .{ 3, 4 } } },
        .{ .input = "a\n\n", .want = &.{ .{ 0, 1 }, .{ 2, 2 } } },
        .{ .input = "a\r\nb", .want = &.{ .{ 0, 1 }, .{ 3, 4 } } },
    };
    for (cases) |case| {
        var found: [8][2]usize = undefined;
        var n: usize = 0;
        var pos: usize = 0;
        var it = unicode.text(case.input).terminators().iterator();
        while (it.next()) |t| {
            found[n] = .{ pos, t.start.value };
            n += 1;
            pos = t.end.value;
        }
        if (pos < case.input.len) {
            found[n] = .{ pos, case.input.len };
            n += 1;
        }
        try std.testing.expectEqual(case.want.len, n);
        for (case.want, found[0..n]) |want, got| try std.testing.expectEqualDeep(want, got);
    }
}

test "ASCII arrays agree with the fused record" {
    // The trie is verified exhaustively against the pinned UCD by
    // src/tools/test-properties.py. What that cannot see is scalar.at's ASCII
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

test "word bounds partition the view and name their own types" {
    const line = "The price is $9.99 -unless you pay cash.";

    // The named types are part of the surface: a caller can store the view,
    // the iterator and one item without naming an anonymous type.
    const bounds: unicode.WordBounds = unicode.text(line).wordBounds();
    var it: unicode.WordBoundIterator = bounds.iterator();
    var first: unicode.WordBound = undefined;

    var words: usize = 0;
    var segments: usize = 0;
    var cursor: usize = 0;
    while (it.next()) |segment| : (segments += 1) {
        if (segments == 0) first = segment;
        try std.testing.expectEqual(cursor, segment.start.value);
        cursor = segment.end.value;
        if (segment.is_word) words += 1;
    }
    try std.testing.expectEqual(line.len, cursor);
    try std.testing.expectEqual(@as(usize, 18), segments);
    try std.testing.expectEqual(@as(usize, 8), words);
    try std.testing.expectEqualStrings("The", line[first.start.value..first.end.value]);
    try std.testing.expect(first.is_word);

    // Opening the view scans nothing, and an exhausted iterator stays null.
    try std.testing.expectEqual(@as(?unicode.WordBound, null), it.next());
    var empty = unicode.text("").wordBounds().iterator();
    try std.testing.expectEqual(@as(?unicode.WordBound, null), empty.next());
}

test "codepoints yield the same view as cp without eager properties" {
    const bytes = "a\u{754c}\u{fffd}\u{1f600}\x00\u{10ffff}";
    const points: unicode.Codepoints = unicode.text(bytes).codepoints();
    var it: unicode.CodepointIterator = points.iterator();
    const values = [_]u21{ 'a', 0x754c, 0xfffd, 0x1f600, 0, 0x10ffff };
    const ends = [_]usize{ 1, 4, 7, 11, 12, 16 };
    try std.testing.expectEqual(@as(usize, 0), it.offset);
    try std.testing.expectEqual(@as(?unicode.DecodeError, null), it.err);
    for (values, ends) |value, end| {
        const point: unicode.Codepoint = it.next().?;
        try std.testing.expectEqualDeep(unicode.cp(value), point);
        try std.testing.expectEqual(end, it.offset);
        try std.testing.expectEqual(@as(?unicode.DecodeError, null), it.err);
    }
    try std.testing.expectEqual(bytes.len, it.offset);
    try std.testing.expectEqual(@as(?unicode.CodepointView, null), it.next());
    try std.testing.expectEqual(@as(?unicode.CodepointView, null), it.next());
    try std.testing.expectEqual(@as(?unicode.DecodeError, null), it.err);
    try std.testing.expectEqual(bytes.len, it.offset);
}

test "codepoints stop at malformed UTF-8 and retain error and byte offset" {
    const invalids = [_][]const u8{
        "\xffvalid", "\x80valid", "\xc0\x80valid", // illegal lead, stray continuation, overlong
        "\xc2", "\xe2\x82", "\xf0\x9f\x98", // truncation
        "\xc2A", "\xe2\x82A", "\xf0\x9f\x98A", // broken continuation
        "\xed\xa0\x80", "\xf4\x90\x80\x80", // surrogate, above Unicode range
        "\xe0\x80\x80", "\xf0\x80\x80\x80", // overlong 3/4-byte forms
    };
    for (invalids) |invalid| {
        var buffer: [32]u8 = undefined;
        const prefix = "a\u{754c}";
        @memcpy(buffer[0..prefix.len], prefix);
        @memcpy(buffer[prefix.len..][0..invalid.len], invalid);
        // Test both an error at the start and an error following valid scalars.
        for ([_][]const u8{ invalid, buffer[0 .. prefix.len + invalid.len] }, [_]usize{ 0, prefix.len }) |bytes, failure_offset| {
            var it = unicode.text(bytes).codepoints().iterator();
            var count: usize = 0;
            while (it.next()) |_| count += 1;
            try std.testing.expectEqual(@as(usize, if (failure_offset == 0) 0 else 2), count);
            try std.testing.expectEqual(failure_offset, it.offset);
            try std.testing.expectEqual(unicode.DecodeError.invalid_utf8, it.err.?);
            try std.testing.expectEqual(@as(?unicode.CodepointView, null), it.next());
            try std.testing.expectEqual(@as(?unicode.CodepointView, null), it.next());
            try std.testing.expectEqual(failure_offset, it.offset);
            try std.testing.expectEqual(unicode.DecodeError.invalid_utf8, it.err.?);
        }
    }
}

test "empty and copied codepoint iterators retain independent state" {
    var empty = unicode.text("").codepoints().iterator();
    try std.testing.expectEqual(@as(?unicode.CodepointView, null), empty.next());
    try std.testing.expectEqual(@as(?unicode.CodepointView, null), empty.next());
    try std.testing.expectEqual(@as(?unicode.DecodeError, null), empty.err);
    try std.testing.expectEqual(@as(usize, 0), empty.offset);

    var it = unicode.text("a\xff").codepoints().iterator();
    try std.testing.expectEqual(@as(u21, 'a'), it.next().?.value);
    var checkpoint = it;
    try std.testing.expectEqual(@as(?unicode.CodepointView, null), it.next());
    try std.testing.expectEqual(@as(?unicode.DecodeError, null), checkpoint.err);
    try std.testing.expectEqual(@as(usize, 1), checkpoint.offset);
    try std.testing.expectEqual(@as(?unicode.CodepointView, null), checkpoint.next());
    try std.testing.expectEqual(unicode.DecodeError.invalid_utf8, checkpoint.err.?);
}

test "the pinned Unicode data version is published" {
    try std.testing.expectEqual(@as(u64, 17), unicode.unicode_version.major);
    try std.testing.expectEqual(@as(u64, 0), unicode.unicode_version.minor);
    try std.testing.expectEqual(@as(u64, 0), unicode.unicode_version.patch);
    // This is the data version, not the package version; the three verifiers
    // under src/tools assert it against the vendored UCD filenames.
    try std.testing.expect(unicode.unicode_version.pre == null);
}

test "normalization and capacity are reached from the text view" {
    const capacity = comptime try unicode.text("cafe\u{0301}").normalizedLenBound(.nfc);
    try std.testing.expectEqual(@as(usize, 18), capacity);
    try std.testing.expectEqual(@as(usize, 0), try unicode.text("").normalizedLenBound(.nfd));
    var buffer: [capacity]u8 = undefined;
    // Composed input, decomposed output, and the reverse.
    try std.testing.expectEqualSlices(u8, "cafe\u{0301}", try unicode.text("caf\u{00E9}").normalize(.nfd).writeTo(&buffer));
    try std.testing.expectEqualSlices(u8, "caf\u{00E9}", try unicode.text("cafe\u{0301}").normalize(.nfc).writeTo(&buffer));

    var it: unicode.NormalizationIterator(.nfd) = unicode.text("\u{1E69}").normalize(.nfd);
    for ([_]u21{ 's', 0x0323, 0x0307 }) |expected| {
        try std.testing.expectEqual(expected, (try it.next()).?);
    }
    try std.testing.expect((try it.next()) == null);
}

test "exactly four normalization forms" {
    // NFC, NFD, NFKC, NFKD -- canonical and compatibility, each with and
    // without composition. The count is asserted so adding a fifth form (or
    // removing one of these four) is a deliberate act, not an accident.
    try std.testing.expectEqual(@as(usize, 4), @typeInfo(unicode.Form).@"enum".fields.len);
    try std.testing.expectEqual(@as(usize, 2), @typeInfo(unicode.Equivalence).@"enum".fields.len);
}

test "code-point width and East Asian wide answer different questions" {
    // U+302A IDEOGRAPHIC LEVEL TONE MARK: Mn, and East_Asian_Width=Wide.
    // Category forces width to zero regardless of east_asian_wide.
    try std.testing.expect(unicode.cp(0x302A).isEastAsianWide());
    try std.testing.expectEqual(@as(u2, 0), unicode.cp(0x302A).width());

    // U+FF61 HALFWIDTH IDEOGRAPHIC FULL STOP: East_Asian_Width=Halfwidth.
    // east_asian_wide is true (it covers H too), but width only treats
    // Wide/Fullwidth as two columns, so this measures one.
    try std.testing.expect(unicode.cp(0xFF61).isEastAsianWide());
    try std.testing.expectEqual(@as(u2, 1), unicode.cp(0xFF61).width());

    // An ordinary CJK ideograph agrees on both questions.
    try std.testing.expect(unicode.cp(0x4E00).isEastAsianWide());
    try std.testing.expectEqual(@as(u2, 2), unicode.cp(0x4E00).width());

    try std.testing.expect(!unicode.cp('a').isEastAsianWide());
    try std.testing.expectEqual(@as(u2, 1), unicode.cp('a').width());
}

test "iterated code-point views expose property groups" {
    const bytes = "a\u{200D}\u{1F1FA}\u{fffd}";
    var it = unicode.text(bytes).codepoints().iterator();
    while (it.next()) |point| {
        try std.testing.expectEqualDeep(unicode.cp(point.value).general(), point.general());
        try std.testing.expectEqualDeep(unicode.cp(point.value).terminal(), point.terminal());
        try std.testing.expectEqualDeep(unicode.cp(point.value).grapheme(), point.grapheme());
        try std.testing.expectEqual(unicode.cp(point.value).width(), point.width());
    }
    try std.testing.expectEqual(@as(?unicode.DecodeError, null), it.err);
    try std.testing.expectEqual(unicode.GraphemeClass.zwj, unicode.cp(0x200D).grapheme().gcb);
    try std.testing.expectEqual(unicode.GraphemeClass.regional_indicator, unicode.cp(0x1F1FA).grapheme().gcb);
}

test "general group agrees with the pinned UCD" {
    const Want = struct {
        cp: u21,
        category: unicode.GeneralCategory,
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
        const props = unicode.cp(want.cp).general();
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
    try std.testing.expect(unicode.cp('A').general().isCased);
    try std.testing.expect(unicode.cp('A').general().category == .lu);
}

test "code-point groups preserve table facts across the complete u21 domain" {
    const tables = @import("tables");
    var raw: u32 = 0;
    while (raw <= std.math.maxInt(u21)) : (raw += 1) {
        const value: u21 = @intCast(raw);
        const point = unicode.cp(value);
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
        const grapheme = point.grapheme();
        const expected_grapheme = tables.properties.graphemeProperties(value);
        try std.testing.expectEqual(expected_grapheme.gcb, grapheme.gcb);
        try std.testing.expectEqual(expected_grapheme.incb, grapheme.incb);
        try std.testing.expectEqual(expected_grapheme.extended_pictographic, grapheme.extendedPictographic);
        try std.testing.expectEqual(tables.properties.codepointWidth(value), point.width());
        try std.testing.expectEqual(tables.properties.isEastAsianWide(value), point.isEastAsianWide());
    }
}
