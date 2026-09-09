const std = @import("std");
const zunic = @import("zunic");

test "docs: terminal graphemes skip surrounding escapes" {
    const bytes = "\x1b[31mcafe\u{0301}\x1b[0m";
    var it = zunic.terminal(bytes).graphemes().iterator();
    for ([_][]const u8{ "c", "a", "f", "e\u{0301}" }) |expected| {
        const span = (try it.next()).?;
        try std.testing.expectEqualStrings(expected, bytes[span.start.value..span.end.value]);
    }
    try std.testing.expect((try it.next()) == null);
}

test "docs: terminal grapheme rejects an internal escape" {
    const bytes = "e\x1b[31m\u{0301}";
    var it = zunic.terminal(bytes).graphemes().iterator();
    try std.testing.expectError(error.EscapeInsideGrapheme, it.next());
}

test "docs: measured graphemes" {
    const bytes = "e\u{0301}界";
    var it = zunic.text(bytes).graphemes().measured().iterator();
    const accent = it.next().?;
    try std.testing.expectEqualStrings("e\u{0301}", bytes[accent.start.value..accent.end.value]);
    try std.testing.expectEqual(@as(u2, 1), accent.columns);
    const ideograph = it.next().?;
    try std.testing.expectEqual(@as(u2, 2), ideograph.columns);
    try std.testing.expect(it.next() == null);
}

test "docs: width" {
    try std.testing.expectEqual(@as(usize, 3), zunic.text("e\u{0301}界").width());
    try std.testing.expectEqual(@as(usize, 2), zunic.text("🇬🇷").width());
    try std.testing.expectEqual(@as(usize, 2), zunic.text("a\nb").width());
    try std.testing.expectEqual(@as(usize, 0), zunic.text("\t\xff").width());
}

test "docs: terminator gaps" {
    const bytes = "one\r\ntwo\u{2028}three";
    const terms = zunic.text(bytes).terminators();
    try std.testing.expectEqual(@as(usize, 2), terms.count());
    var it = terms.iterator();
    var start: usize = 0;
    const expected = [_][]const u8{ "one", "two" };
    var index: usize = 0;
    while (it.next()) |term| {
        try std.testing.expectEqualStrings(expected[index], bytes[start..term.start.value]);
        start = term.end.value;
        index += 1;
    }
    try std.testing.expectEqualStrings("three", bytes[start..]);
}

test "docs: wrapping" {
    const bytes = "one two";
    const wrapped = try zunic.text(bytes).wrap(.{ .max_columns = 4 });
    try std.testing.expectEqual(@as(usize, 2), wrapped.count());
    var it = wrapped.iterator();
    const first = it.next().?;
    try std.testing.expectEqualStrings("one ", bytes[first.start.value..first.end.value]);
    try std.testing.expectEqual(@as(usize, 4), first.columns.value);
    const second = it.next().?;
    try std.testing.expectEqualStrings("two", bytes[second.start.value..second.end.value]);
    try std.testing.expect(it.next() == null);

    const wide = try zunic.text("abcdef").wrap(.{ .max_columns = 3, .overflow = .allow });
    try std.testing.expectEqual(@as(usize, 1), wide.count());
}

test "docs: word-like segments" {
    const bytes = "Hello, world!";
    var it = zunic.text(bytes).wordBounds().iterator();
    const expected = [_][]const u8{ "Hello", "world" };
    var count: usize = 0;
    while (it.next()) |segment| {
        if (!segment.is_word) continue;
        try std.testing.expectEqualStrings(expected[count], bytes[segment.start.value..segment.end.value]);
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), count);
}

test "docs: normalization output" {
    const bytes = "cafe\u{0301}";
    const capacity = comptime try zunic.text(bytes).normalizedLenBound(.nfc);
    var buffer: [capacity]u8 = undefined;
    const result = try zunic.text(bytes).normalize(.nfc).writeTo(&buffer);
    try std.testing.expectEqualStrings("café", result);
    try std.testing.expectEqual(@as(usize, 4), zunic.text(result).width());

    var scalars = zunic.text("é").normalize(.nfd);
    try std.testing.expectEqual(@as(u21, 'e'), (try scalars.next()).?);
    try std.testing.expectEqual(@as(u21, 0x301), (try scalars.next()).?);
    try std.testing.expect((try scalars.next()) == null);
}

test "docs: normalization queries" {
    try std.testing.expect(try zunic.text("café").eql("cafe\u{0301}", .canonical));
    try std.testing.expect(try zunic.text("café").isNormalized(.nfc));
    try std.testing.expect(!try zunic.text("café").isNormalized(.nfd));
    try std.testing.expect(!try zunic.text("ﬁ").eql("fi", .canonical));
}

test "docs: normalization capacity and iterator position" {
    const capacity = comptime try zunic.text("é").normalizedLenBound(.nfd);
    try std.testing.expectEqual(@as(usize, 6), capacity);
    var it = zunic.text("é").normalize(.nfd);
    _ = try it.next(); // Consume 'e'.
    var buffer: [capacity]u8 = undefined;
    try std.testing.expectEqualStrings("\u{0301}", try it.writeTo(&buffer));
    // writeTo copied the iterator; its next scalar is still the accent.
    try std.testing.expectEqual(@as(u21, 0x301), (try it.next()).?);
}

test "docs: the pinned Unicode data version" {
    // The version of the Unicode data every table is generated from. Not the
    // package version, and unrelated to the Zig version in use.
    try std.testing.expectEqual(@as(u64, 16), zunic.unicode_version.major);
    try std.testing.expectEqual(@as(u64, 0), zunic.unicode_version.minor);
    try std.testing.expectEqual(@as(u64, 0), zunic.unicode_version.patch);
}

test "docs: normalize from the text view" {
    var buffer: [64]u8 = undefined;
    // Normalize either form through the text view.
    try std.testing.expectEqualStrings("caf\u{00E9}", try zunic.text("cafe\u{0301}").normalize(.nfc).writeTo(&buffer));
    try std.testing.expectEqualStrings("cafe\u{0301}", try zunic.text("caf\u{00E9}").normalize(.nfd).writeTo(&buffer));
}

test "docs: quick check, including maybe" {
    // Yes and no are definite.
    try std.testing.expectEqual(zunic.QuickCheck.yes, try zunic.text("caf\u{00E9}").isNormalizedQuick(.nfc));
    try std.testing.expectEqual(zunic.QuickCheck.no, try zunic.text("caf\u{00E9}").isNormalizedQuick(.nfd));

    // Maybe means the answer needs context this check does not gather. Both
    // of these are maybe; only the authoritative query separates them.
    try std.testing.expectEqual(zunic.QuickCheck.maybe, try zunic.text("q\u{0301}").isNormalizedQuick(.nfc));
    try std.testing.expectEqual(zunic.QuickCheck.maybe, try zunic.text("a\u{0301}").isNormalizedQuick(.nfc));
    try std.testing.expect(try zunic.text("q\u{0301}").isNormalized(.nfc));
    try std.testing.expect(!try zunic.text("a\u{0301}").isNormalized(.nfc));
}
