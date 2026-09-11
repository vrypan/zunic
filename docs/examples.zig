const std = @import("std");
const zunic = @import("zunic");

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
    try std.testing.expectEqual(@as(u64, 17), zunic.unicode_version.major);
    try std.testing.expectEqual(@as(u64, 0), zunic.unicode_version.minor);
    try std.testing.expectEqual(@as(u64, 0), zunic.unicode_version.patch);
}

test "docs: terminal properties, case folding, and streaming graphemes" {
    const terminal = zunic.terminalProperties(0x1f600);
    try std.testing.expectEqual(zunic.EastAsianWidth.wide, terminal.east_asian_width);
    try std.testing.expect(terminal.emoji_presentation);
    try std.testing.expect(zunic.isEmojiVariationBase(0x231b));

    const width = zunic.widthProperties(0x1f3fb);
    try std.testing.expectEqual(@as(u2, 2), width.standalone);
    try std.testing.expect(width.zero_in_grapheme);

    const folded = zunic.fullCaseFold(0x00df);
    try std.testing.expectEqualSlices(u21, &.{ 's', 's' }, folded.slice());

    // Each retained result owns a [3]u21 buffer, so scalar keys can be folded
    // and compared without allocating.
    const kelvin = zunic.fullCaseFold(0x212a);
    const ascii_k = zunic.fullCaseFold('K');
    try std.testing.expect(std.mem.eql(u21, kelvin.slice(), ascii_k.slice()));

    var state: zunic.GraphemeState = .{};
    try std.testing.expect(!zunic.graphemeBreak('e', 0x0301, &state));
    const checkpoint = state;
    try std.testing.expect(zunic.graphemeBreak(0x0301, 'x', &state));
    state = checkpoint;
    try std.testing.expect(!zunic.graphemeBreak(0x0301, 0x0308, &state));
}

test "docs: normalize from the text view" {
    var buffer: [64]u8 = undefined;
    // Normalize either canonical form through the text view.
    try std.testing.expectEqualStrings("caf\u{00E9}", try zunic.text("cafe\u{0301}").normalize(.nfc).writeTo(&buffer));
    try std.testing.expectEqualStrings("cafe\u{0301}", try zunic.text("caf\u{00E9}").normalize(.nfd).writeTo(&buffer));
}

test "docs: NFKC/NFKD and compatibility equality" {
    // A ligature plus an accented letter: NFC/NFD leave the ligature alone,
    // since it has no *canonical* decomposition; NFKC/NFKD expand it, in
    // addition to doing everything NFC/NFD already do.
    const bytes = "\u{FB01}sh\u{00E9}"; // "ﬁshé"
    var buffer: [16]u8 = undefined;
    try std.testing.expectEqualStrings("\u{FB01}sh\u{00E9}", try zunic.text(bytes).normalize(.nfc).writeTo(&buffer));
    try std.testing.expectEqualStrings("fishe\u{0301}", try zunic.text(bytes).normalize(.nfkd).writeTo(&buffer));

    // The ligature is already NFC-normalized -- NFC never applies a
    // compatibility mapping -- but not NFKC-normalized.
    try std.testing.expect(try zunic.text("\u{FB01}").isNormalized(.nfc));
    try std.testing.expect(!try zunic.text("\u{FB01}").isNormalized(.nfkc));

    // Compatibility equality treats the ligature and its expansion as the
    // same text; canonical equality, the default distinction, does not.
    try std.testing.expect(try zunic.text("\u{FB01}").eql("fi", .compatibility));
    try std.testing.expect(!try zunic.text("\u{FB01}").eql("fi", .canonical));

    // Buffer sizing must use the form actually being produced: NFKC/NFKD can
    // expand up to 11x, well past NFC/NFD's 3x.
    try std.testing.expectEqual(@as(usize, 33), try zunic.text("\u{FDFA}").normalizedLenBound(.nfkd));
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

test "docs: trim and print" {
    const input = "\u{00a0} Hello, 世界! \n";
    const trimmed = zunic.text(input).trim();
    // Print the retained bytes; the result borrows `input`.
    try std.testing.expectEqualStrings("Hello, 世界!", trimmed.bytes);
    try std.testing.expectEqual(@as(usize, 12), trimmed.width());

    // Offsets from the trimmed view index the trimmed bytes.
    var graphemes = trimmed.graphemes().iterator();
    const first = graphemes.next().?;
    try std.testing.expectEqualStrings("H", trimmed.bytes[first.start.value..first.end.value]);

    // One end at a time.
    try std.testing.expectEqualStrings("hi  ", zunic.text("  hi  ").trimStart().bytes);
    try std.testing.expectEqualStrings("  hi", zunic.text("  hi  ").trimEnd().bytes);

    // Whitespace is Unicode 17.0.0 White_Space: no-break spaces go, zero-width
    // characters stay, and a malformed edge byte stops the scan.
    try std.testing.expectEqualStrings("x", zunic.text("\u{202F}x\u{3000}").trim().bytes);
    try std.testing.expectEqualStrings("\u{200B}x\u{FEFF}", zunic.text("\u{200B}x\u{FEFF}").trim().bytes);
    try std.testing.expectEqualStrings("\xff", zunic.text(" \xff ").trim().bytes);
}

test "docs: trim then chain" {
    const trimmed = zunic.text("  cafe\u{0301} \u{3000}").trim();
    try std.testing.expectEqualStrings("cafe\u{0301}", trimmed.bytes);
    try std.testing.expectEqual(@as(usize, 4), trimmed.width());
    try std.testing.expect(try trimmed.eql("caf\u{00E9}", .canonical));

    var buffer: [16]u8 = undefined;
    try std.testing.expectEqualStrings("caf\u{00E9}", try trimmed.normalize(.nfc).writeTo(&buffer));

    const wrapped = try zunic.text("  alpha beta gamma  ").trim().wrap(.{ .max_columns = 10 });
    try std.testing.expectEqual(@as(usize, 2), wrapped.count());
}

test "docs: Text.isWhitespace while iterating graphemes" {
    const bytes = "Hello,   \u{4E16}\u{754C}! \t\n";
    const view = zunic.text(bytes);
    var graphemes = view.graphemes().iterator();
    var whitespace_count: usize = 0;
    var content_count: usize = 0;
    while (graphemes.next()) |span| {
        if (view.isWhitespace(span)) {
            whitespace_count += 1;
        } else {
            content_count += 1;
        }
    }
    // H, e, l, l, o, comma, 世, 界, ! -- nine content clusters.
    try std.testing.expectEqual(@as(usize, 9), content_count);
    // Three spaces after the comma, one after "!", one tab, one newline.
    try std.testing.expectEqual(@as(usize, 6), whitespace_count);
}

test "docs: isAscii on bytes and Text" {
    // Same check through a free function and a method on the text view.
    try std.testing.expect(zunic.isAscii("Hello, world!"));
    try std.testing.expect(zunic.text("Hello, world!").isAscii());

    // A byte-range test, not UTF-8 validation: any byte 0x80 or above fails
    // it, whether it is part of valid UTF-8 or malformed input.
    try std.testing.expect(!zunic.isAscii("caf\u{00E9}"));
    try std.testing.expect(!zunic.isAscii("\xff"));

    // ASCII controls, including ESC, count as ASCII.
    try std.testing.expect(zunic.isAscii("\x00\x1b\x7f"));
}
