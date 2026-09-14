const std = @import("std");
const unicode = @import("zunic");

test "cp keeps its concrete constructor type" {
    const constructor: *const fn (u21) unicode.CodepointView = &unicode.cp;
    try std.testing.expectEqual(@as(u21, 'A'), constructor('A').value);
    try std.testing.expectEqual(@as(u21, 0x10ffff), unicode.cp(0x10ffff).value);
}

test "public Reader codepoint API" {
    var input: std.Io.Reader = .fixed("A\u{20ac}");
    const source: unicode.Reader = unicode.reader(&input);
    var it: unicode.ReaderCodepointIterator = source.codepoints();
    try std.testing.expectEqual(@as(u21, 'A'), (try it.next()).?.value);
    const euro = (try it.next()).?;
    try std.testing.expectEqual(@as(u21, 0x20ac), euro.value);
    try std.testing.expectEqual(unicode.Script.common, euro.script());
    try std.testing.expect((try it.next()) == null);
}

test "Reader and strict slice iterators have deterministic malformed parity" {
    var prng = std.Random.DefaultPrng.init(0x037_c0de);
    var bytes: [32]u8 = undefined;
    for (0..10_000) |_| {
        prng.random().bytes(&bytes);
        const len = prng.random().intRangeAtMost(usize, 4, bytes.len);
        var input: std.Io.Reader = .fixed(bytes[0..len]);
        var stream = unicode.reader(&input).codepoints();
        var slice = unicode.text(bytes[0..len]).codepoints().iterator();
        while (true) {
            const expected = slice.next();
            const actual = stream.next() catch |err| {
                try std.testing.expectEqual(error.InvalidUtf8, err);
                try std.testing.expectEqual(unicode.DecodeError.invalid_utf8, slice.err.?);
                try std.testing.expectEqual(@as(u64, @intCast(slice.offset)), stream.offset);
                break;
            };
            try std.testing.expectEqual(expected == null, actual == null);
            if (expected) |point| try std.testing.expectEqual(point.value, actual.?.value);
            try std.testing.expectEqual(@as(u64, @intCast(slice.offset)), stream.offset);
            if (expected == null) break;
        }
    }
}

test "unicode component compiles as an independent root" {
    const step = unicode.utf8.step("x");
    try std.testing.expectEqual(@as(usize, 1), step.len);
    try std.testing.expectEqual(@as(usize, 2), unicode.text("🇬🇷").width());
}

test "Script properties are exposed by the public facade" {
    const primary: unicode.Script = unicode.cp('A').script();
    try std.testing.expectEqual(unicode.Script.latin, primary);
    try std.testing.expectEqualSlices(unicode.Script, &.{ .hiragana, .katakana }, unicode.cp(0x30fc).scriptExtensions());
}

test "bidirectional properties are exposed by the public facade" {
    const props: unicode.BidiProperties = unicode.cp('(').bidi();
    try std.testing.expectEqual(unicode.BidiClass.other_neutral, props.class);
    try std.testing.expectEqual(unicode.BidiPairedBracketType.open, props.pairedBracketType);
    try std.testing.expectEqual(@as(?u21, ')'), unicode.cp('(').bidiMirroringGlyph());
    try std.testing.expectEqual(@as(?u21, ')'), unicode.cp('(').bidiPairedBracket());
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
