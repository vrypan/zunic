//! Everything the Unicode fixture does not pin: buffer occupancy, the
//! configured sequence limit, malformed input, output-capacity behaviour,
//! iterator copy semantics, and the two queries.
const std = @import("std");
const zunic = @import("zunic");
const normalization = @import("normalization");
const properties = @import("tables").normalization;

const Form = normalization.Form;
const limit = normalization.max_nonstarters;

fn expectNfd(input: []const u8, expected: []const u8) !void {
    var buffer: [4096]u8 = undefined;
    try std.testing.expectEqualSlices(u8, expected, try normalization.normalize(input, .nfd).writeTo(&buffer));
}

fn expectNfc(input: []const u8, expected: []const u8) !void {
    var buffer: [4096]u8 = undefined;
    try std.testing.expectEqualSlices(u8, expected, try normalization.normalize(input, .nfc).writeTo(&buffer));
}

// ---------------------------------------------------------------- basics

test "empty input normalizes to nothing" {
    var buffer: [4]u8 = undefined;
    try std.testing.expectEqual(@as(usize, 0), (try normalization.normalize("", .nfc).writeTo(&buffer)).len);
    try std.testing.expectEqual(@as(usize, 0), (try normalization.normalize("", .nfd).writeTo(&buffer)).len);
    var it = normalization.normalize("", .nfd);
    try std.testing.expectEqual(@as(?u21, null), try it.next());
    // Repeated calls after successful exhaustion keep returning null.
    try std.testing.expectEqual(@as(?u21, null), try it.next());
    try std.testing.expectEqual(@as(?u21, null), try it.next());
}

test "ASCII passes through untouched" {
    try expectNfc("hello, world!", "hello, world!");
    try expectNfd("hello, world!", "hello, world!");
}

test "the plan's pinned regression cases" {
    // Singletons decompose but never recompose.
    try expectNfc("\u{212A}", "K"); // KELVIN SIGN -> K
    try expectNfd("\u{212A}", "K");
    try expectNfc("K", "K"); // and never back again
    try expectNfc("\u{1FEF}", "\u{0060}");
    try expectNfd("\u{1FEF}", "\u{0060}");
    try expectNfc("\u{0060}", "\u{0060}");
    // U+0344 is a composition exclusion: it decomposes and stays decomposed.
    try expectNfd("\u{0344}", "\u{0308}\u{0301}");
    try expectNfc("\u{0344}", "\u{0308}\u{0301}");
    // Four-scalar recursive decomposition, and the NFD 3x witness.
    try expectNfd("\u{0390}", "\u{03B9}\u{0308}\u{0301}");
    try std.testing.expectEqual(@as(usize, 6), "\u{03B9}\u{0308}\u{0301}".len);
    try std.testing.expectEqual(@as(usize, 2), "\u{0390}".len);
    // The NFC 3x witness: four bytes in, twelve out.
    try expectNfc("\u{1D160}", "\u{1D158}\u{1D165}\u{1D16E}");
    try std.testing.expectEqual(@as(usize, 12), "\u{1D158}\u{1D165}\u{1D16E}".len);
}

test "Hangul is algorithmic in both directions" {
    // LVT: three bytes decompose to three three-byte jamo, the other 3x case.
    try expectNfd("\u{D4DB}", "\u{1111}\u{1171}\u{11B6}");
    try expectNfc("\u{1111}\u{1171}\u{11B6}", "\u{D4DB}");
    // LV, with no trailing consonant.
    try expectNfd("\u{AC00}", "\u{1100}\u{1161}");
    try expectNfc("\u{1100}\u{1161}", "\u{AC00}");
    // L + V + T arrive as three separate starters, so composition has to
    // reach across two run boundaries.
    try expectNfc("\u{1100}\u{1161}\u{11A8}", "\u{AC01}");
    // U+11A7 is the trailing-consonant filler and must not attach.
    try expectNfc("\u{AC00}\u{11A7}", "\u{AC00}\u{11A7}");
}

test "canonical ordering is stable and by combining class" {
    // U+0301 is class 230, U+0327 is class 202: ordering swaps them.
    try expectNfd("q\u{0301}\u{0327}", "q\u{0327}\u{0301}");
    try expectNfc("q\u{0301}\u{0327}", "\u{0071}\u{0327}\u{0301}");
    // Equal classes keep their input order.
    try expectNfd("a\u{0300}\u{0301}", "a\u{0300}\u{0301}");
    try expectNfd("a\u{0301}\u{0300}", "a\u{0301}\u{0300}");
    // ...which is exactly why these two are not canonically equivalent.
    try std.testing.expect(!try normalization.eql("a\u{0300}\u{0301}", "a\u{0301}\u{0300}", .canonical));
}

test "composition is blocked by an intervening mark of equal or greater class" {
    // U+0328 (class 202) does not block U+0301 (class 230) from the A.
    try expectNfc("A\u{0328}\u{0301}", "\u{0104}\u{0301}");
    // But a second class-230 mark blocks the one after it.
    try expectNfc("a\u{0300}\u{0301}", "\u{00E0}\u{0301}");
}

test "leading combining marks form a run with no starter" {
    try expectNfd("\u{0301}\u{0327}", "\u{0327}\u{0301}");
    try expectNfc("\u{0301}\u{0327}", "\u{0327}\u{0301}");
    try expectNfc("\u{0327}a", "\u{0327}a");
}

// ------------------------------------------------------- output capacity

test "writeTo reports NoSpace without writing a partial encoding" {
    // NFD of U+00E9 is two bytes plus two: "e" then U+0301.
    const input = "\u{00E9}";
    var buffer: [8]u8 = undefined;
    @memset(&buffer, 0xAA);

    // One byte short of the three the output needs.
    try std.testing.expectError(error.NoSpace, normalization.normalize(input, .nfd).writeTo(buffer[0..2]));
    // The "e" was written; the mark's two bytes were not started.
    try std.testing.expectEqual(@as(u8, 'e'), buffer[0]);
    try std.testing.expectEqual(@as(u8, 0xAA), buffer[1]);
    // Bytes past the destination slice are untouched.
    try std.testing.expectEqual(@as(u8, 0xAA), buffer[2]);

    // Exactly sufficient.
    @memset(&buffer, 0xAA);
    try std.testing.expectEqualSlices(u8, "e\u{0301}", try normalization.normalize(input, .nfd).writeTo(buffer[0..3]));
    try std.testing.expectEqual(@as(u8, 0xAA), buffer[3]);

    // At the published bound, and larger than it.
    const bound = try normalization.normalizedLenBound(input.len, .nfd);
    try std.testing.expectEqual(@as(usize, 6), bound);
    try std.testing.expectEqualSlices(u8, "e\u{0301}", try normalization.normalize(input, .nfd).writeTo(buffer[0..bound]));
    try std.testing.expectEqualSlices(u8, "e\u{0301}", try normalization.normalize(input, .nfd).writeTo(&buffer));

    // Zero-length destination: fine for empty input, NoSpace otherwise.
    try std.testing.expectEqual(@as(usize, 0), (try normalization.normalize("", .nfd).writeTo(buffer[0..0])).len);
    try std.testing.expectError(error.NoSpace, normalization.normalize("a", .nfd).writeTo(buffer[0..0]));
}

test "a three-byte NFC Hangul result fits in three bytes" {
    // Its NFD form is nine bytes, so sizing the destination from the
    // intermediate representation would reject a destination that suffices.
    var buffer: [3]u8 = undefined;
    try std.testing.expectEqualSlices(u8, "\u{D4DB}", try normalization.normalize("\u{1111}\u{1171}\u{11B6}", .nfc).writeTo(&buffer));
}

test "normalizedLenBound arithmetic at its edges" {
    try std.testing.expectEqual(@as(usize, 0), try normalization.normalizedLenBound(0, .nfc));
    try std.testing.expectEqual(@as(usize, 3), try normalization.normalizedLenBound(1, .nfd));
    const largest = std.math.maxInt(usize) / 3;
    try std.testing.expectEqual(largest * 3, try normalization.normalizedLenBound(largest, .nfc));
    try std.testing.expectError(error.Overflow, normalization.normalizedLenBound(largest + 1, .nfc));
    try std.testing.expectError(error.Overflow, normalization.normalizedLenBound(std.math.maxInt(usize), .nfd));
}

// ------------------------------------------------------ iterator identity

test "a copied iterator traverses independently" {
    var original = normalization.normalize("a\u{0301}bc", .nfd);
    try std.testing.expectEqual(@as(?u21, 'a'), try original.next());

    var copy = original;
    try std.testing.expectEqual(@as(?u21, 0x0301), try copy.next());
    try std.testing.expectEqual(@as(?u21, 'b'), try copy.next());
    // The original is where it was, not where the copy went.
    try std.testing.expectEqual(@as(?u21, 0x0301), try original.next());

    // writeTo takes the iterator by value: it resumes from the receiver's
    // position and leaves the receiver alone.
    var buffer: [16]u8 = undefined;
    try std.testing.expectEqualSlices(u8, "bc", try original.writeTo(&buffer));
    try std.testing.expectEqualSlices(u8, "bc", try original.writeTo(&buffer));
    try std.testing.expectEqual(@as(?u21, 'b'), try original.next());
}

test "writeTo chains off a temporary and matches scalar iteration" {
    var buffer: [64]u8 = undefined;
    const written = try normalization.normalize("Cafe\u{0301} nai\u{0308}ve", .nfc).writeTo(&buffer);
    try std.testing.expectEqualSlices(u8, "Caf\u{00E9} na\u{00EF}ve", written);

    var iterated: [64]u8 = undefined;
    var len: usize = 0;
    var it = normalization.normalize("Cafe\u{0301} nai\u{0308}ve", .nfc);
    while (try it.next()) |cp| len += try std.unicode.utf8Encode(cp, iterated[len..]);
    try std.testing.expectEqualSlices(u8, written, iterated[0..len]);
}

test "the named iterator types are part of the surface" {
    var nfd: zunic.NormalizationIterator(.nfd) = zunic.text("a\u{0301}").normalize(.nfd);
    var nfc: zunic.NormalizationIterator(.nfc) = zunic.text("a\u{0301}").normalize(.nfc);
    const form: zunic.Form = .nfc;
    _ = form;
    try std.testing.expectEqual(@as(?u21, 'a'), try nfd.next());
    try std.testing.expectEqual(@as(?u21, 0x00E1), try nfc.next());
    var buffer: [8]u8 = undefined;
    try std.testing.expectEqualSlices(u8, "\u{0301}", try nfd.writeTo(&buffer));
}

// ---------------------------------------------------- the sequence limit

/// `base` followed by `count` distinct-class combining marks.
///
/// The marks are drawn from a fixed set of classes so a long run really does
/// exercise ordering rather than repeating one scalar.
fn manyMarks(buffer: []u8, base: []const u8, count: usize) []const u8 {
    const marks = [_]u21{ 0x0316, 0x0317, 0x0318, 0x0319, 0x031C, 0x031D, 0x0300, 0x0301, 0x0302, 0x0303 };
    @memcpy(buffer[0..base.len], base);
    var len = base.len;
    for (0..count) |i| len += std.unicode.utf8Encode(marks[i % marks.len], buffer[len..]) catch unreachable;
    return buffer[0..len];
}

/// `base` followed by `count` marks that all share combining class 230, so
/// the result is already canonically ordered whatever order they arrive in.
fn sameClassMarks(buffer: []u8, base: []const u8, count: usize) []const u8 {
    @memcpy(buffer[0..base.len], base);
    var len = base.len;
    for (0..count) |i| {
        const mark: u21 = @intCast(0x0300 + i % 16);
        len += std.unicode.utf8Encode(mark, buffer[len..]) catch unreachable;
    }
    return buffer[0..len];
}

test "runs at, below and above the configured limit" {
    var input: [4096]u8 = undefined;
    var output: [8192]u8 = undefined;

    inline for ([_]Form{ .nfd, .nfc, .nfkd, .nfkc }) |form| {
        // One below and exactly at the limit both succeed.
        _ = try normalization.normalize(manyMarks(&input, "a", limit - 1), form).writeTo(&output);
        _ = try normalization.normalize(manyMarks(&input, "a", limit), form).writeTo(&output);
        // One above is rejected, through writeTo and through direct iteration.
        const over = manyMarks(&input, "a", limit + 1);
        try std.testing.expectError(error.SequenceTooLong, normalization.normalize(over, form).writeTo(&output));

        var it = normalization.normalize(over, form);
        var seen: usize = 0;
        while (it.next() catch |err| {
            try std.testing.expectEqual(error.SequenceTooLong, err);
            break;
        }) |_| seen += 1;
        // The failure is permanent.
        try std.testing.expectError(error.SequenceTooLong, it.next());
        try std.testing.expectError(error.SequenceTooLong, it.next());
        // Nothing of the over-limit run was emitted: the starter is buffered
        // with it, so the run is rejected before any of it is ordered.
        try std.testing.expectEqual(@as(usize, 0), seen);
    }
}

test "an oversized destination does not buy a longer run" {
    var input: [4096]u8 = undefined;
    var output: [8192]u8 = undefined;
    const over = manyMarks(&input, "a", limit + 1);
    try std.testing.expect(output.len > try normalization.normalizedLenBound(over.len, .nfd));
    try std.testing.expectError(error.SequenceTooLong, normalization.normalize(over, .nfd).writeTo(&output));
}

test "a starter resets the run, so many short runs are fine" {
    var input: [16384]u8 = undefined;
    var output: [49152]u8 = undefined;
    var len: usize = 0;
    // Sized from the configured limit rather than a guess, so a larger
    // -Dnormalization-buffer-bytes does not overrun the fixture.
    const runs = @min(64, input.len / (1 + 2 * limit) - 1);
    for (0..runs) |_| {
        const chunk = manyMarks(input[len..], "a", limit);
        len += chunk.len;
    }
    _ = try normalization.normalize(input[0..len], .nfd).writeTo(&output);
    _ = try normalization.normalize(input[0..len], .nfc).writeTo(&output);
}

test "leading marks count toward the limit" {
    var input: [4096]u8 = undefined;
    var output: [8192]u8 = undefined;
    _ = try normalization.normalize(manyMarks(&input, "", limit), .nfd).writeTo(&output);
    try std.testing.expectError(
        error.SequenceTooLong,
        normalization.normalize(manyMarks(&input, "", limit + 1), .nfd).writeTo(&output),
    );
}

test "the limit counts decomposed marks, not encoded scalars" {
    // Every U+0390 decomposes to a starter and two marks, and U+0344 to two
    // marks, so a handful of scalars crosses the limit.
    var input: [4096]u8 = undefined;
    var output: [8192]u8 = undefined;
    var len: usize = 0;
    @memcpy(input[0..1], "a");
    len = 1;
    var marks: usize = 0;
    while (marks <= limit) : (marks += 2) {
        len += std.unicode.utf8Encode(0x0344, input[len..]) catch unreachable;
    }
    try std.testing.expectError(error.SequenceTooLong, normalization.normalize(input[0..len], .nfd).writeTo(&output));
    // NFC must not hide it either: composition happens after the count.
    try std.testing.expectError(error.SequenceTooLong, normalization.normalize(input[0..len], .nfc).writeTo(&output));
}

test "the configured limit is what the build option says" {
    try std.testing.expectEqual(@as(usize, 4), @sizeOf(u32));
    try std.testing.expectEqual(normalization.buffer_bytes / 4, normalization.buffer_entries);
    try std.testing.expectEqual(normalization.buffer_entries - 2, limit);
    try std.testing.expect(normalization.buffer_bytes % 32 == 0 and normalization.buffer_bytes > 0);
}

test "large configured runs exceed u16 without overflowing" {
    const marks = std.math.maxInt(u16);
    if (limit < marks) return error.SkipZigTest;
    const input = "a" ++ "\u{0305}" ** marks;
    inline for ([_]Form{ .nfd, .nfc, .nfkd, .nfkc }) |form| {
        var it = normalization.normalize(input, form);
        try std.testing.expectEqual(@as(?u21, 'a'), try it.next());
        for (0..marks) |_| try std.testing.expectEqual(@as(?u21, 0x0305), try it.next());
        try std.testing.expectEqual(@as(?u21, null), try it.next());
    }
}

// -------------------------------------------------------- malformed input

const malformed = [_][]const u8{
    "\x80", // isolated continuation byte
    "\xbf",
    "\xc0\x80", // overlong
    "\xc1\xbf",
    "\xe0\x80\x80",
    "\xed\xa0\x80", // surrogate
    "\xf0\x80\x80\x80",
    "\xf4\x90\x80\x80", // above U+10FFFF
    "\xf5\x80\x80\x80",
    "\xff",
    "\xc2", // truncated
    "\xe2\x82",
    "\xf0\x9f\x91",
};

test "malformed UTF-8 is an error, never a replacement character" {
    var output: [64]u8 = undefined;
    for (malformed) |bad| {
        inline for ([_]Form{ .nfd, .nfc, .nfkd, .nfkc }) |form| {
            try std.testing.expectError(error.InvalidUtf8, normalization.normalize(bad, form).writeTo(&output));

            // In a prefix, in a suffix, and between marks.
            var prefixed: [64]u8 = undefined;
            @memcpy(prefixed[0..bad.len], bad);
            @memcpy(prefixed[bad.len..][0..3], "a\u{0301}");
            try std.testing.expectError(error.InvalidUtf8, normalization.normalize(prefixed[0 .. bad.len + 3], form).writeTo(&output));

            var suffixed: [64]u8 = undefined;
            @memcpy(suffixed[0..3], "a\u{0301}");
            @memcpy(suffixed[3..][0..bad.len], bad);
            try std.testing.expectError(error.InvalidUtf8, normalization.normalize(suffixed[0 .. 3 + bad.len], form).writeTo(&output));
        }
    }
}

test "the decoding failure is permanent and leaves earlier output valid" {
    // Normalization runs one combining run ahead of its output, so the error
    // preempts the run still being accumulated: "b" was read but not yet
    // emittable, because a following mark could have reordered or composed
    // into it. Everything actually returned is correct.
    var it = normalization.normalize("ab\xff", .nfd);
    try std.testing.expectEqual(@as(?u21, 'a'), try it.next());
    try std.testing.expectError(error.InvalidUtf8, it.next());
    try std.testing.expectError(error.InvalidUtf8, it.next());

    // writeTo keeps the prefix it had already written.
    var output: [16]u8 = undefined;
    @memset(&output, 0xAA);
    try std.testing.expectError(error.InvalidUtf8, normalization.normalize("ab\xff", .nfd).writeTo(&output));
    try std.testing.expectEqualSlices(u8, "a", output[0..1]);
    try std.testing.expectEqual(@as(u8, 0xAA), output[1]);

    // A starter after the bad byte changes nothing: the error still wins.
    try std.testing.expectError(error.InvalidUtf8, normalization.normalize("ab\xffc", .nfd).writeTo(&output));
}

test "a bad encoding is rejected however much room the destination has" {
    var output: [4096]u8 = undefined;
    try std.testing.expectError(error.InvalidUtf8, normalization.normalize("\xff", .nfd).writeTo(&output));
}

test "a literal U+FFFD is ordinary input" {
    try expectNfc("\u{FFFD}", "\u{FFFD}");
    try expectNfd("a\u{FFFD}b", "a\u{FFFD}b");
    // Two different malformed inputs must not become equal by decaying to it.
    try std.testing.expectError(error.InvalidUtf8, normalization.eql("\xff", "\xfe", .canonical));
    try std.testing.expectError(error.InvalidUtf8, normalization.eql("\xff", "\u{FFFD}", .canonical));
}

// ------------------------------------------------------------------- eql

test "canonical equivalence over differently encoded text" {
    try std.testing.expect(try normalization.eql("caf\u{00E9}", "cafe\u{0301}", .canonical));
    try std.testing.expect(try normalization.eql("", "", .canonical));
    try std.testing.expect(try normalization.eql("\u{1E69}", "s\u{0323}\u{0307}", .canonical));
    try std.testing.expect(try normalization.eql("\u{D4DB}", "\u{1111}\u{1171}\u{11B6}", .canonical));
    // Reordered but canonically equal.
    try std.testing.expect(try normalization.eql("q\u{0301}\u{0327}", "q\u{0327}\u{0301}", .canonical));
    // Compatibility equivalence is a different relation and must not leak in.
    try std.testing.expect(!try normalization.eql("\u{FB01}", "fi", .canonical));
    try std.testing.expect(!try normalization.eql("\u{FF41}", "a", .canonical));
    try std.testing.expect(!try normalization.eql("\u{2075}", "5", .canonical));
    // Differences at the very end are still found.
    try std.testing.expect(!try normalization.eql("cafe\u{0301}x", "caf\u{00E9}y", .canonical));
    try std.testing.expect(!try normalization.eql("caf\u{00E9}", "caf\u{00E9}x", .canonical));
    try std.testing.expect(!try normalization.eql("caf\u{00E9}x", "caf\u{00E9}", .canonical));
}

test "eql propagates errors from either operand" {
    try std.testing.expectError(error.InvalidUtf8, normalization.eql("\xff", "a", .canonical));
    try std.testing.expectError(error.InvalidUtf8, normalization.eql("a", "\xff", .canonical));
    var input: [4096]u8 = undefined;
    const over = manyMarks(&input, "a", limit + 1);
    var other: [4096]u8 = undefined;
    const copy = manyMarks(&other, "a", limit + 1);
    // Even identical over-limit inputs reach the limit check rather than
    // short-circuiting on byte equality.
    try std.testing.expectError(error.SequenceTooLong, normalization.eql(over, copy, .canonical));
    try std.testing.expectError(error.SequenceTooLong, normalization.eql(over, "a", .canonical));
    try std.testing.expectError(error.SequenceTooLong, normalization.eql("a", over, .canonical));
}

fn expectNotEqualOrRejected(a: []const u8, b: []const u8) !void {
    const answer = normalization.eql(a, b, .canonical) catch |err| {
        try std.testing.expectEqual(error.SequenceTooLong, err);
        return;
    };
    try std.testing.expect(!answer);
}

test "eql agrees with comparing normalized output" {
    var prng = std.Random.DefaultPrng.init(0x023_cafe_d00d);
    const random = prng.random();
    const alphabet = [_]u21{ 'a', 'b', 0x0300, 0x0301, 0x0327, 0x00E9, 0x0065, 0x1E69, 0x0323, 0x0307, 0xAC00, 0x1100, 0x1161, 0x212A, 0x004B, 0x0344 };
    var left: [256]u8 = undefined;
    var right: [256]u8 = undefined;
    var left_nfd: [1024]u8 = undefined;
    var right_nfd: [1024]u8 = undefined;
    for (0..20_000) |_| {
        var a: usize = 0;
        var b: usize = 0;
        for (0..random.uintLessThan(usize, 8)) |_|
            a += std.unicode.utf8Encode(alphabet[random.uintLessThan(usize, alphabet.len)], left[a..]) catch unreachable;
        for (0..random.uintLessThan(usize, 8)) |_|
            b += std.unicode.utf8Encode(alphabet[random.uintLessThan(usize, alphabet.len)], right[b..]) catch unreachable;
        // A small -Dnormalization-buffer-bytes can reject a randomly generated
        // run. eql compares in lockstep, so it may find a difference and stop
        // before reaching the over-long part; it may never call two inputs
        // equal when one of them cannot be normalized.
        const one = normalization.normalize(left[0..a], .nfd).writeTo(&left_nfd) catch |err| {
            try std.testing.expectEqual(error.SequenceTooLong, err);
            try expectNotEqualOrRejected(left[0..a], right[0..b]);
            continue;
        };
        const other = normalization.normalize(right[0..b], .nfd).writeTo(&right_nfd) catch |err| {
            try std.testing.expectEqual(error.SequenceTooLong, err);
            try expectNotEqualOrRejected(left[0..a], right[0..b]);
            continue;
        };
        try std.testing.expectEqual(std.mem.eql(u8, one, other), try normalization.eql(left[0..a], right[0..b], .canonical));

        // NFD(a) == NFD(b) exactly when NFC(a) == NFC(b): the relation does
        // not depend on which form you compare in.
        const nfd_equal = std.mem.eql(u8, one, other);
        const one_c = try normalization.normalize(left[0..a], .nfc).writeTo(&left_nfd);
        const other_c = try normalization.normalize(right[0..b], .nfc).writeTo(&right_nfd);
        try std.testing.expectEqual(nfd_equal, std.mem.eql(u8, one_c, other_c));
    }
}

// ---------------------------------------------------------- isNormalized

test "isNormalized agrees with normalizing" {
    const cases = [_][]const u8{
        "",                  "hello",
        "caf\u{00E9}",       "cafe\u{0301}",
        "q\u{0301}\u{0327}", "q\u{0327}\u{0301}",
        "\u{212A}",          "K",
        "\u{0344}",          "\u{0308}\u{0301}",
        "\u{D4DB}",          "\u{1111}\u{1171}\u{11B6}",
        "\u{AC00}",          "\u{1100}\u{1161}",
        "A\u{0328}\u{0301}", "\u{0104}\u{0301}",
        "a\u{0300}\u{0301}", "\u{00E0}\u{0301}",
        "\u{0301}a",         "a\u{0301}b\u{0327}c",
        "\u{1E69}",          "s\u{0323}\u{0307}",
        "\u{0390}",          "\u{03B9}\u{0308}\u{0301}",
        "e\u{0301}\u{0301}", "\u{00E9}\u{0301}",
        "\u{1D160}",         "\u{1D158}\u{1D165}\u{1D16E}",
    };
    var buffer: [256]u8 = undefined;
    for (cases) |input| {
        inline for ([_]Form{ .nfc, .nfd, .nfkc, .nfkd }) |form| {
            const normalized = try normalization.normalize(input, form).writeTo(&buffer);
            std.testing.expectEqual(
                std.mem.eql(u8, input, normalized),
                try normalization.isNormalized(input, form),
            ) catch |err| {
                std.debug.print("isNormalized({s}, .{s}) on \"{f}\"\n", .{
                    @tagName(form), @tagName(form), std.ascii.hexEscape(input, .lower),
                });
                return err;
            };
        }
    }
}

/// `isNormalized` must agree with actually normalizing, or report the same
/// resource error. Extracted so the inline loop over forms contains no
/// control flow that would have to escape a runtime loop.
fn checkIsNormalized(input: []const u8, comptime form: Form, buffer: []u8) !void {
    const normalized = normalization.normalize(input, form).writeTo(buffer) catch |err| {
        try std.testing.expectEqual(error.SequenceTooLong, err);
        // isNormalized is licensed to short-circuit: a decisive `false` found
        // before the over-long run may leave the rest unread. What it must
        // never do is answer `true` about input it could not normalize.
        const answer = normalization.isNormalized(input, form) catch |query_err| {
            try std.testing.expectEqual(error.SequenceTooLong, query_err);
            return;
        };
        try std.testing.expect(!answer);
        return;
    };
    std.testing.expectEqual(
        std.mem.eql(u8, input, normalized),
        try normalization.isNormalized(input, form),
    ) catch |err| {
        std.debug.print("isNormalized .{s} on \"{f}\"\n", .{ @tagName(form), std.ascii.hexEscape(input, .lower) });
        return err;
    };
}

test "isNormalized agrees with normalizing over random streams" {
    var prng = std.Random.DefaultPrng.init(0x023_15_b0bcafe);
    const random = prng.random();
    const alphabet = [_]u21{ 'a', 0x0300, 0x0301, 0x0327, 0x00E9, 0x1E69, 0x0323, 0x0307, 0xAC00, 0x1100, 0x1161, 0x11A8, 0x212A, 0x0344, 0x0F73, 0x0958 };
    var input: [256]u8 = undefined;
    var buffer: [1024]u8 = undefined;
    for (0..20_000) |_| {
        var len: usize = 0;
        for (0..random.uintLessThan(usize, 10)) |_|
            len += std.unicode.utf8Encode(alphabet[random.uintLessThan(usize, alphabet.len)], input[len..]) catch unreachable;
        try checkIsNormalized(input[0..len], .nfc, &buffer);
        try checkIsNormalized(input[0..len], .nfd, &buffer);
    }
}

test "isNormalized rejects marks that are merely out of order" {
    // Both marks are NFD_QC=Yes and NFC_QC=Yes individually; only their order
    // makes the string un-normalized.
    try std.testing.expect(!try normalization.isNormalized("q\u{0301}\u{0327}", .nfd));
    try std.testing.expect(!try normalization.isNormalized("q\u{0301}\u{0327}", .nfc));
    try std.testing.expect(try normalization.isNormalized("q\u{0327}\u{0301}", .nfd));
}

test "isNormalized propagates errors and short-circuits before an unread suffix" {
    var input: [4096]u8 = undefined;
    try std.testing.expectError(error.InvalidUtf8, normalization.isNormalized("a\xff", .nfc));
    try std.testing.expectError(error.InvalidUtf8, normalization.isNormalized("a\xff", .nfd));
    // Long already-normalized runs stay within the limit. These marks all
    // share class 230, so any order of them is already canonical; manyMarks
    // deliberately mixes classes and is not normalized.
    try std.testing.expect(try normalization.isNormalized(sameClassMarks(&input, "a", limit), .nfd));
    // Mixed classes in the wrong order are not normalized, whatever the limit.
    try std.testing.expect(!try normalization.isNormalized("a\u{0301}\u{0327}", .nfd));
    // ...and one mark more is a resource error, not a false.
    try std.testing.expectError(
        error.SequenceTooLong,
        normalization.isNormalized(sameClassMarks(&input, "a", limit + 1), .nfd),
    );
    // A decisive false may leave a malformed suffix unread. This pins the
    // documented behaviour rather than requiring a prevalidation pass.
    try std.testing.expect(!try normalization.isNormalized("\u{212A}\xff", .nfd));
}

test "isNormalized counts marks inside precomposed starters" {
    // U+0305 is NFC_QC=Yes, so no Maybe fallback can hide a bad fast count.
    inline for (.{ .{ "\u{00E9}", 1 }, .{ "\u{0390}", 2 } }) |case| {
        const starter = case[0];
        const hidden_marks = case[1];
        const at_limit = starter ++ "\u{0305}" ** (limit - hidden_marks);
        const over_limit = at_limit ++ "\u{0305}";
        var output: [over_limit.len * 3]u8 = undefined;
        try std.testing.expect(try zunic.text(at_limit).isNormalized(.nfc));
        try std.testing.expectEqualSlices(u8, at_limit, try zunic.text(at_limit).normalize(.nfc).writeTo(&output));
        try std.testing.expectError(error.SequenceTooLong, zunic.text(over_limit).isNormalized(.nfc));
        inline for ([_]Form{ .nfd, .nfc, .nfkd, .nfkc }) |form| {
            try std.testing.expectError(error.SequenceTooLong, zunic.text(over_limit).normalize(form).writeTo(&output));
        }
        // A new starter resets the decomposed count.
        try std.testing.expect(try zunic.text(at_limit ++ "x" ++ at_limit).isNormalized(.nfc));
    }
}

// ------------------------------------------------------------ public API

test "the queries are reachable from the text view" {
    try std.testing.expect(try zunic.text("caf\u{00E9}").eql("cafe\u{0301}", .canonical));
    try std.testing.expect(!try zunic.text("\u{FB01}").eql("fi", .canonical));
    try std.testing.expect(try zunic.text("caf\u{00E9}").isNormalized(.nfc));
    try std.testing.expect(!try zunic.text("caf\u{00E9}").isNormalized(.nfd));

    const bound = try zunic.text("cafe\u{0301}").normalizedLenBound(.nfc);
    var buffer: [64]u8 = undefined;
    try std.testing.expect(bound <= buffer.len);
    try std.testing.expectEqualSlices(u8, "caf\u{00E9}", try zunic.text("cafe\u{0301}").normalize(.nfc).writeTo(buffer[0..bound]));
}

test "the table module agrees with the engine on Hangul" {
    // Hangul is the one mapping the engine computes rather than reads, so the
    // tables must not also contain it.
    var cp: u21 = 0xAC00;
    while (cp < 0xAC00 + 11172) : (cp += 1) {
        try std.testing.expect(properties.decomposition(cp) == null);
        try std.testing.expectEqual(@as(u8, 0), properties.combiningClass(cp));
    }
}

test "the class trie agrees with the sorted tables it replaced" {
    // The Python verifier decodes the emitted arrays and never runs these
    // functions, so the trie's own indexing is only covered here. Walk every
    // code point and check the class against the tables that still carry the
    // mappings, plus the two range guards that survive.
    var cp: u21 = 0;
    while (cp < 0x110000) : (cp += 1) {
        if (cp >= 0xD800 and cp <= 0xDFFF) continue;
        const class = properties.classOf(cp);

        // `decomposes` must agree with the decomposition table, Hangul aside:
        // Hangul is algorithmic and deliberately absent from the table.
        const hangul = cp >= 0xAC00 and cp < 0xAC00 + 11172;
        const in_table = properties.decomposition(cp) != null;
        try std.testing.expectEqual(class.decomposes, in_table or hangul);
        try std.testing.expectEqual(!class.decomposes, properties.nfdQuickCheckIsYes(cp));
        try std.testing.expectEqual(class.ccc, properties.combiningClass(cp));
        try std.testing.expectEqual(class.quick_check, properties.nfcQuickCheck(cp));

        // Nothing that is not a base can absorb, and nothing that is not
        // composable can be absorbed -- for any partner at all.
        if (!class.composable) {
            for ([_]u21{ 'a', 'A', 0x00C0, 0x05D0, 0x0915, 0x4E00 }) |base|
                try std.testing.expect(properties.compose(base, cp) == null);
        }
        if (!class.composition_base) {
            for ([_]u21{ 0x0300, 0x0301, 0x0323, 0x0327, 0x093C }) |mark|
                try std.testing.expect(properties.compose(cp, mark) == null);
        }
    }
    // A class id must fit the byte the trie stores, and the table must be
    // small enough to stay resident.
    try std.testing.expect(properties.class_table.len < 256);
    try std.testing.expectEqual(@as(usize, 2), @sizeOf(properties.Class));
}

fn containsDecomposition(cp: u21) bool {
    for (properties.decomposition_entries) |entry| if (entry & 0x3FFFF == cp) return true;
    return false;
}

test "a Maybe that needs the general check, and one that does not" {
    // Both of these put a class-220 mark after a starter whose own
    // decomposition ends in class 230, so decomposing reorders inside the run
    // and the fast path in `isNormalized` must decline to answer. They then
    // disagree, which is why no purely local rule can settle a Maybe.
    //
    // U+00E9 is e + U+0301. Adding U+0323 sorts it in front of the acute, and
    // e + U+0323 has a composite (U+1EB9), so the text normalizes to something
    // else and is not NFC.
    try std.testing.expect(!try normalization.isNormalized("\u{00E9}\u{0323}", .nfc));
    try expectNfc("\u{00E9}\u{0323}", "\u{1EB9}\u{0301}");

    // U+1E69 is s + U+0323 + U+0307. Adding a second U+0323 also reorders,
    // but recomposition puts every character back, so the input *is* NFC.
    try std.testing.expect(try normalization.isNormalized("\u{1E69}\u{0323}", .nfc));
    try expectNfc("\u{1E69}\u{0323}", "\u{1E69}\u{0323}");

    // The fast path proper: a starter with no hidden marks, so no reordering
    // is possible and one composition lookup settles it.
    try std.testing.expect(try normalization.isNormalized("z\u{0300}", .nfc)); // no z-grave
    try std.testing.expect(!try normalization.isNormalized("a\u{0300}", .nfc)); // a-grave is U+00E0
    // Blocked, so the acute cannot reach the starter even though a+acute exists.
    try std.testing.expect(try normalization.isNormalized("a\u{0305}\u{0301}", .nfc));
    // Hangul reaches across a starter boundary.
    try std.testing.expect(!try normalization.isNormalized("\u{1100}\u{1161}", .nfc));
    try std.testing.expect(try normalization.isNormalized("\u{AC00}", .nfc));
}

// ------------------------------------------------------------ quick check

const QuickCheck = normalization.QuickCheck;

fn quick(input: []const u8, comptime form: Form) !QuickCheck {
    return normalization.isNormalizedQuick(input, form);
}

test "quick check: definite answers" {
    try std.testing.expectEqual(QuickCheck.yes, try quick("", .nfc));
    try std.testing.expectEqual(QuickCheck.yes, try quick("", .nfd));
    try std.testing.expectEqual(QuickCheck.yes, try quick("hello", .nfc));
    try std.testing.expectEqual(QuickCheck.yes, try quick("hello", .nfd));

    // A composed accent decomposes, so NFD is a definite no.
    try std.testing.expectEqual(QuickCheck.no, try quick("caf\u{00E9}", .nfd));
    // Hangul decomposes algorithmically and is in no table.
    try std.testing.expectEqual(QuickCheck.no, try quick("\u{AC00}", .nfd));
    try std.testing.expectEqual(QuickCheck.yes, try quick("\u{1100}\u{1161}", .nfd));

    // NFC_QC = No is a definite no for NFC.
    try std.testing.expectEqual(QuickCheck.no, try quick("\u{0344}", .nfc));
    // Marks out of canonical order: no, in either form.
    try std.testing.expectEqual(QuickCheck.no, try quick("q\u{0301}\u{0327}", .nfc));
    try std.testing.expectEqual(QuickCheck.no, try quick("q\u{0301}\u{0327}", .nfd));
    try std.testing.expectEqual(QuickCheck.yes, try quick("q\u{0327}\u{0301}", .nfd));
}

test "quick check: NFD is never maybe" {
    var buffer: [4096]u8 = undefined;
    for ([_][]const u8{ "", "a", "caf\u{00E9}", "cafe\u{0301}", "\u{AC00}", "\u{1100}\u{1161}", "z\u{0300}", "\u{1E69}\u{0323}", "\u{0301}\u{0327}" }) |input|
        try std.testing.expect(try quick(input, .nfd) != .maybe);
    try std.testing.expect(try quick(sameClassMarks(&buffer, "a", limit + 40), .nfd) != .maybe);
}

test "quick check: maybe, settling both ways" {
    // U+0301 is NFC_QC=Maybe. "q" is not a composition base at all, so
    // q+acute stays decomposed and is NFC; a+acute composes to U+00E1 and is
    // not. The quick check says maybe to both, which is the point of the
    // third value. ("z" would be wrong here: z+acute is U+017A.)
    try std.testing.expectEqual(QuickCheck.maybe, try quick("q\u{0301}", .nfc));
    try std.testing.expectEqual(QuickCheck.maybe, try quick("a\u{0301}", .nfc));
    try std.testing.expect(try normalization.isNormalized("q\u{0301}", .nfc));
    try std.testing.expect(!try normalization.isNormalized("a\u{0301}", .nfc));

    // A later definite no overrides an earlier maybe.
    try std.testing.expectEqual(QuickCheck.no, try quick("q\u{0301} \u{0344}", .nfc));
    try std.testing.expectEqual(QuickCheck.no, try quick("q\u{0301} a\u{0301}\u{0327}", .nfc));
}

test "quick check: the whole slice is scanned" {
    // Malformed bytes after a decisive no are still reported, unlike
    // isNormalized, which may stop early.
    try std.testing.expectError(error.InvalidUtf8, quick("\xff", .nfc));
    try std.testing.expectError(error.InvalidUtf8, quick("\u{0344}\xff", .nfc));
    try std.testing.expectError(error.InvalidUtf8, quick("caf\u{00E9}\xff", .nfd));
    try std.testing.expectError(error.InvalidUtf8, quick("q\u{0301}\u{0327}\xff", .nfd));
    // ...whereas the authoritative query is allowed to stop at the no.
    try std.testing.expect(!try normalization.isNormalized("\u{212A}\xff", .nfd));
}

test "quick check ignores the configured run limit" {
    // A run longer than the buffer is perfectly normalized, and the bounded
    // normalizer still refuses it. Quick check answers the Unicode question.
    var buffer: [8192]u8 = undefined;
    const long = sameClassMarks(&buffer, "a", limit + 1);
    try std.testing.expectEqual(QuickCheck.yes, try quick(long, .nfd));
    var output: [16384]u8 = undefined;
    try std.testing.expectError(error.SequenceTooLong, normalization.normalize(long, .nfd).writeTo(&output));
    try std.testing.expectError(error.SequenceTooLong, normalization.isNormalized(long, .nfd));
}

/// A definite quick check must agree with the authoritative query. Extracted
/// so the inline loop over forms holds no control flow that would have to
/// escape the runtime loop around it.
fn checkQuickAgainstDefinitive(bytes: []const u8, comptime form: Form) !void {
    const answer = normalization.isNormalized(bytes, form) catch |err| {
        // Over the run limit. Quick check does not enforce it, so it may
        // still answer definitely and there is nothing to cross-check.
        try std.testing.expectEqual(error.SequenceTooLong, err);
        return;
    };
    switch (try quick(bytes, form)) {
        .yes => try std.testing.expect(answer),
        .no => try std.testing.expect(!answer),
        .maybe => {},
    }
}

test "a definite quick check never contradicts the authoritative query" {
    var prng = std.Random.DefaultPrng.init(0x026_9c_a11a);
    const random = prng.random();
    const alphabet = [_]u21{ 'a', 'z', 0x0300, 0x0301, 0x0327, 0x00E9, 0x1E69, 0x0323, 0x0307, 0xAC00, 0x1100, 0x1161, 0x11A8, 0x212A, 0x0344, 0x0F73 };
    var input: [128]u8 = undefined;
    for (0..20_000) |_| {
        var len: usize = 0;
        for (0..random.uintLessThan(usize, 8)) |_|
            len += std.unicode.utf8Encode(alphabet[random.uintLessThan(usize, alphabet.len)], input[len..]) catch unreachable;
        try checkQuickAgainstDefinitive(input[0..len], .nfc);
        try checkQuickAgainstDefinitive(input[0..len], .nfd);
    }
}

test "quick check reaches the text view" {
    try std.testing.expectEqual(QuickCheck.yes, try zunic.text("caf\u{00E9}").isNormalizedQuick(.nfc));
    try std.testing.expectEqual(QuickCheck.no, try zunic.text("caf\u{00E9}").isNormalizedQuick(.nfd));
    try std.testing.expectEqual(QuickCheck.maybe, try zunic.text("q\u{0301}").isNormalizedQuick(.nfc));
}

// --------------------------------------------------------- NFKC and NFKD

fn expectNfkd(input: []const u8, expected: []const u8) !void {
    var buffer: [4096]u8 = undefined;
    try std.testing.expectEqualSlices(u8, expected, try normalization.normalize(input, .nfkd).writeTo(&buffer));
}

fn expectNfkc(input: []const u8, expected: []const u8) !void {
    var buffer: [4096]u8 = undefined;
    try std.testing.expectEqualSlices(u8, expected, try normalization.normalize(input, .nfkc).writeTo(&buffer));
}

test "NFC and NFD never apply a compatibility mapping" {
    const compat_mapped = [_][]const u8{
        "\u{FB01}", // LATIN SMALL LIGATURE FI
        "\u{FF21}", // FULLWIDTH LATIN CAPITAL LETTER A
        "\u{2460}", // CIRCLED DIGIT ONE
        "\u{00B2}", // SUPERSCRIPT TWO
        "\u{00A0}", // NO-BREAK SPACE
    };
    for (compat_mapped) |input| {
        try expectNfc(input, input);
        try expectNfd(input, input);
    }
}

test "NFKC and NFKD apply compatibility mappings NFC/NFD do not" {
    try expectNfkd("\u{FB01}", "fi"); // ligature
    try expectNfkc("\u{FB01}", "fi");
    try expectNfkd("\u{FF21}", "A"); // fullwidth
    try expectNfkc("\u{FF21}", "A");
    try expectNfkd("\u{2460}", "1"); // circled digit
    try expectNfkc("\u{2460}", "1");
    try expectNfkd("\u{00B2}", "2"); // superscript
    try expectNfkc("\u{00B2}", "2");
    try expectNfkd("\u{00A0}", " "); // no-break space
    try expectNfkc("\u{00A0}", " ");
}

test "a recursive compatibility mapping: compatibility target that itself canonically decomposes" {
    // U+01C4 LATIN CAPITAL LETTER DZ WITH CARON has the compatibility
    // mapping <compat> 0044 017D ("D" + U+017D), and U+017D itself
    // canonically decomposes to "Z" + combining caron -- so the full NFKD
    // recurses through both a compatibility and a canonical step.
    try expectNfkd("\u{01C4}", "DZ\u{030C}");
    // NFKC recomposes the canonical part (Z + caron -> U+017D) but the
    // compatibility boundary is never rebuilt: the result is "D" + U+017D,
    // not the original ligature-style U+01C4.
    try expectNfkc("\u{01C4}", "D\u{017D}");
}

test "a canonical decomposition that changes meaning under NFKC but not NFC" {
    // U+0385 GREEK DIALYTIKA TONOS decomposes canonically to U+00A8 U+0301.
    // NFC leaves it alone (its own NFC_QC is Yes). But U+00A8 DIAERESIS has a
    // compatibility mapping to U+0020 U+0308, so NFKD replaces it with a
    // plain space carrying the two marks -- and composition can never
    // recover U+0385 from a space, so NFKC changes it too.
    try expectNfc("\u{0385}", "\u{0385}");
    try expectNfd("\u{0385}", "\u{00A8}\u{0301}");
    try expectNfkd("\u{0385}", " \u{0308}\u{0301}");
    try expectNfkc("\u{0385}", " \u{0308}\u{0301}");
    try std.testing.expect(try normalization.isNormalized("\u{0385}", .nfc));
    try std.testing.expect(!try normalization.isNormalized("\u{0385}", .nfkc));
    try std.testing.expectEqual(QuickCheck.yes, try normalization.isNormalizedQuick("\u{0385}", .nfc));
    try std.testing.expectEqual(QuickCheck.no, try normalization.isNormalizedQuick("\u{0385}", .nfkc));
}

test "the generated maximum compatibility expansion witness" {
    // U+FDFA ARABIC LIGATURE SALLALLAHOU ALAYHE WASALLAM: 18 scalars, the
    // measured maximum recursive expansion under NFKD (verified exhaustively
    // by test-normalization-properties.py, not just for this one witness).
    const expected = "\u{635}\u{644}\u{649} \u{627}\u{644}\u{644}\u{647} \u{639}\u{644}\u{64a}\u{647} \u{648}\u{633}\u{644}\u{645}";
    try expectNfkd("\u{FDFA}", expected);
    // None of the 18 scalars are combining marks and no adjacent pair is a
    // canonical composition, so NFKC leaves the decomposition exactly as is
    // rather than recomposing anything.
    try expectNfkc("\u{FDFA}", expected);

    // Exact-size and undersized buffers, mirroring the canonical witness
    // tests: writeTo must succeed with exactly enough room and fail with one
    // byte less, without writing a partial encoding.
    var exact: [expected.len]u8 = undefined;
    try std.testing.expectEqualStrings(expected, try normalization.normalize("\u{FDFA}", .nfkd).writeTo(&exact));
    var short: [expected.len - 1]u8 = undefined;
    try std.testing.expectError(error.NoSpace, normalization.normalize("\u{FDFA}", .nfkd).writeTo(&short));

    // Scalar iteration agrees with writeTo, over the one input that actually
    // exercises the full compatibility scratch buffer.
    var iterated: [expected.len]u8 = undefined;
    var len: usize = 0;
    var it = normalization.normalize("\u{FDFA}", .nfkd);
    while (try it.next()) |cp| len += try std.unicode.utf8Encode(cp, iterated[len..]);
    try std.testing.expectEqualStrings(expected, iterated[0..len]);
}

test "NFKC and NFKD adjacent to the maximum-expansion witness" {
    // The witness immediately preceded and followed by ordinary content, so
    // an off-by-one in the scratch buffer would corrupt a neighbour rather
    // than only the witness itself.
    try expectNfkd("a\u{FDFA}b", "a\u{635}\u{644}\u{649} \u{627}\u{644}\u{644}\u{647} \u{639}\u{644}\u{64a}\u{647} \u{648}\u{633}\u{644}\u{645}b");
    try expectNfkd("\u{FDFA}\u{FDFA}", "\u{635}\u{644}\u{649} \u{627}\u{644}\u{644}\u{647} \u{639}\u{644}\u{64a}\u{647} \u{648}\u{633}\u{644}\u{645}" ** 2);
}

test "Hangul is algorithmic under NFKD and NFKC too" {
    // NFKD always fully decomposes, the same as NFD.
    try expectNfkd("\u{AC00}", "\u{1100}\u{1161}"); // GA
    try expectNfkd("\u{AC01}", "\u{1100}\u{1161}\u{11A8}"); // GAG
    // NFKC composes L+V and LV+T back arithmetically, the same as NFC: a
    // Hangul syllable round-trips under NFKC exactly as it does under NFC,
    // because canonical composition is unaffected by compatibility mapping.
    try expectNfkc("\u{AC00}", "\u{AC00}");
    try expectNfkc("\u{AC01}", "\u{AC01}");
    try expectNfkc("\u{1100}\u{1161}\u{11A8}", "\u{AC01}");
}

test "singletons are never reversed by NFKC" {
    // NFC maps KELVIN SIGN to K and never the reverse; NFKC must not either,
    // since compatibility mappings are excluded from composition the same
    // way canonical singletons are.
    try expectNfkc("\u{212A}", "K");
    try expectNfkc("K", "K");
    try expectNfkd("\u{212A}", "K");
}

test "composition is blocked under NFKC exactly as under NFC" {
    // Neither input here involves a compatibility mapping, so NFKC's answer
    // must match NFC's proven one exactly -- this checks that composition
    // blocking is genuinely shared between the two forms, not reproved.
    try expectNfkc("A\u{0328}\u{0301}", "\u{0104}\u{0301}");
    try expectNfkc("a\u{0300}\u{0301}", "\u{00E0}\u{0301}");
}

test "eql .compatibility over equivalent and unequal input" {
    try std.testing.expect(try normalization.eql("\u{FB01}", "fi", .compatibility));
    try std.testing.expect(!try normalization.eql("\u{FB01}", "fi", .canonical));
    try std.testing.expect(try normalization.eql("\u{2460}", "1", .compatibility));
    try std.testing.expect(!try normalization.eql("\u{2460}", "2", .compatibility));
    // Canonically equivalent input is also compatibility-equivalent: NFD is
    // a subset of NFKD's decomposition, so nothing here can cancel that out.
    try std.testing.expect(try normalization.eql("cafe\u{0301}", "caf\u{00E9}", .compatibility));
    // Compatibility-only equivalence is never canonical.
    try std.testing.expect(!try normalization.eql("\u{FF21}", "A", .canonical));
}

test "eql .compatibility propagates errors from either operand" {
    try std.testing.expectError(error.InvalidUtf8, normalization.eql("\xff", "fi", .compatibility));
    try std.testing.expectError(error.InvalidUtf8, normalization.eql("\u{FB01}", "\xff", .compatibility));
    var input: [4096]u8 = undefined;
    const over = manyMarks(&input, "a", limit + 1);
    try std.testing.expectError(error.SequenceTooLong, normalization.eql(over, "a", .compatibility));
    try std.testing.expectError(error.SequenceTooLong, normalization.eql("a", over, .compatibility));
}

test "normalizedLenBound for the compatibility forms" {
    // The compatibility factor (11) is distinct from and larger than the
    // canonical one (3): a caller sizing a buffer for NFKC/NFKD must not
    // reuse the canonical bound.
    try std.testing.expectEqual(@as(usize, 33), try normalization.normalizedLenBound(3, .nfkd));
    try std.testing.expectEqual(@as(usize, 33), try normalization.normalizedLenBound(3, .nfkc));
    try std.testing.expectEqual(@as(usize, 9), try normalization.normalizedLenBound(3, .nfd));
    // A compile-time bound, sizing a stack buffer -- the plan's motivating
    // use case, exercised here for a compatibility form specifically.
    const capacity = comptime normalization.normalizedLenBound("\u{FDFA}".len, .nfkd) catch unreachable;
    var buffer: [capacity]u8 = undefined;
    const written = try normalization.normalize("\u{FDFA}", .nfkd).writeTo(&buffer);
    try std.testing.expect(written.len <= capacity);
}

/// A function generic over the normalization form, the shape `Text.normalize`
/// itself has: `comptime form: Form` selects both the iterator type and the
/// scratch/compose behaviour at compile time, with no runtime branch on which
/// form is in use.
fn normalizedLength(comptime form: Form, input: []const u8) !usize {
    var it = normalization.normalize(input, form);
    var count: usize = 0;
    while (try it.next()) |_| count += 1;
    return count;
}

test "compile-time form selection" {
    // "fi" never recomposes: there is no canonical pair for f+i, so NFKC
    // stops at the same two decomposed scalars NFKD produces. NFC/NFD leave
    // the one-scalar ligature untouched, never seeing it as decomposable.
    try std.testing.expectEqual(@as(usize, 2), try normalizedLength(.nfkd, "\u{FB01}"));
    try std.testing.expectEqual(@as(usize, 2), try normalizedLength(.nfkc, "\u{FB01}"));
    try std.testing.expectEqual(@as(usize, 1), try normalizedLength(.nfc, "\u{FB01}"));
    try std.testing.expectEqual(@as(usize, 1), try normalizedLength(.nfd, "\u{FB01}"));
}

test "isNormalized and isNormalizedQuick over compatibility-mapped input" {
    inline for (.{
        .{ "\u{FB01}", false }, .{ "fi", true },
        .{ "\u{00A0}", false }, .{ " ", true },
        .{ "\u{2460}", false }, .{ "1", true },
    }) |case| {
        const input, const expected = case;
        try std.testing.expectEqual(expected, try normalization.isNormalized(input, .nfkc));
        try std.testing.expectEqual(expected, try normalization.isNormalized(input, .nfkd));
        const quick_result = try normalization.isNormalizedQuick(input, .nfkc);
        if (expected) {
            try std.testing.expect(quick_result != .no);
        } else {
            try std.testing.expectEqual(QuickCheck.no, quick_result);
        }
    }
    // NFKD_QC, like NFD_QC, is never Maybe.
    try std.testing.expectEqual(QuickCheck.no, try normalization.isNormalizedQuick("\u{FB01}", .nfkd));
    try std.testing.expectEqual(QuickCheck.yes, try normalization.isNormalizedQuick("fi", .nfkd));
}

test "runs at and beyond the nonstarter limit after compatibility decomposition" {
    // U+FB01's compatibility mapping ("f", "i") is two starters with no
    // marks of its own, so this exercises a run of marks that only begins
    // *after* a compatibility expansion has already been flushed -- a case
    // the generic "'a' plus marks" limit tests never reach, since plain "a"
    // has no compatibility expansion to flush first.
    var input: [4096]u8 = undefined;
    var output: [8192]u8 = undefined;
    inline for ([_]Form{ .nfkc, .nfkd }) |form| {
        _ = try normalization.normalize(manyMarks(&input, "\u{FB01}", limit), form).writeTo(&output);
        const over = manyMarks(&input, "\u{FB01}", limit + 1);
        try std.testing.expectError(error.SequenceTooLong, normalization.normalize(over, form).writeTo(&output));
        // isNormalized short-circuits on the ligature itself (its NFKC_QC/
        // decomposes-under-NFKD answer is already a definite No), so it
        // returns `false` here rather than ever reaching the mark run or
        // the limit -- the documented short-circuit contract, not a special
        // case for compatibility mappings.
        try std.testing.expectEqual(false, try normalization.isNormalized(over, form));
        // isNormalizedQuick does not enforce the limit and is unaffected by
        // it either way.
        _ = try normalization.isNormalizedQuick(over, form);
    }
}

test "NFKC/NFKD reachable from the text view" {
    try std.testing.expect(try zunic.text("\u{FB01}").eql("fi", .compatibility));
    var buffer: [8]u8 = undefined;
    try std.testing.expectEqualStrings("fi", try zunic.text("\u{FB01}").normalize(.nfkd).writeTo(&buffer));
    try std.testing.expectEqualStrings("fi", try zunic.text("\u{FB01}").normalize(.nfkc).writeTo(&buffer));
    // NFC never touches a compatibility-only mapping, so the ligature is
    // already NFC-normalized; NFKC is what changes it.
    try std.testing.expect(try zunic.text("\u{FB01}").isNormalized(.nfc));
    try std.testing.expect(!try zunic.text("\u{FB01}").isNormalized(.nfkc));
    try std.testing.expectEqual(QuickCheck.no, try zunic.text("\u{FB01}").isNormalizedQuick(.nfkc));
}
