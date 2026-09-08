//! Everything the Unicode fixture does not pin: buffer occupancy, the
//! configured sequence limit, malformed input, output-capacity behaviour,
//! iterator copy semantics, and the two queries.
const std = @import("std");
const zunic = @import("root.zig");
const normalization = @import("normalization.zig");
const properties = @import("normalization_properties.zig");

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
    var nfd: zunic.NormalizationIterator(.nfd) = zunic.normalize("a\u{0301}", .nfd);
    var nfc: zunic.NormalizationIterator(.nfc) = zunic.normalize("a\u{0301}", .nfc);
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

    inline for ([_]Form{ .nfd, .nfc }) |form| {
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
    inline for ([_]Form{ .nfd, .nfc }) |form| {
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
        inline for ([_]Form{ .nfd, .nfc }) |form| {
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
        inline for ([_]Form{ .nfc, .nfd }) |form| {
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
        try std.testing.expectEqualSlices(u8, at_limit, try zunic.normalize(at_limit, .nfc).writeTo(&output));
        try std.testing.expectError(error.SequenceTooLong, zunic.text(over_limit).isNormalized(.nfc));
        inline for ([_]Form{ .nfd, .nfc }) |form| {
            try std.testing.expectError(error.SequenceTooLong, zunic.normalize(over_limit, form).writeTo(&output));
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

    const bound = try zunic.normalizedLenBound("cafe\u{0301}".len, .nfc);
    var buffer: [64]u8 = undefined;
    try std.testing.expect(bound <= buffer.len);
    try std.testing.expectEqualSlices(u8, "caf\u{00E9}", try zunic.normalize("cafe\u{0301}", .nfc).writeTo(buffer[0..bound]));
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

test "the accessors' range shortcuts agree with an unguarded search" {
    // The Python verifier decodes the emitted arrays directly, so it checks
    // the data but never runs these functions. The shortcuts they take below
    // `first_decomposition` and friends are therefore only covered here, and a
    // threshold set one code point too high would answer "nothing here" for
    // real data without any table being wrong.
    var cp: u21 = 0;
    while (cp < 0x110000) : (cp += 1) {
        if (cp >= 0xD800 and cp <= 0xDFFF) continue;
        const shortcut = cp < properties.first_decomposition;
        if (shortcut) {
            try std.testing.expect(properties.decomposition(cp) == null);
            try std.testing.expect(properties.nfdQuickCheckIsYes(cp));
        }
        if (cp < properties.first_combining) try std.testing.expectEqual(@as(u8, 0), properties.combiningClass(cp));
        if (cp < properties.first_nfc_relevant)
            try std.testing.expectEqual(properties.QuickCheck.yes, properties.nfcQuickCheck(cp));
        // Nothing below `first_composable` is ever the second half of a
        // composite, whatever it is paired with.
        if (cp < properties.first_composable) {
            for ([_]u21{ 'a', 'A', 0x0041, 0x00C0, 0x1100, 0x05D0 }) |base|
                try std.testing.expect(properties.compose(base, cp) == null);
        }
        // And the shortcut ranges really are empty of data.
        if (shortcut) try std.testing.expect(!containsDecomposition(cp));
    }
    // The thresholds are tight: the code point at each one carries the fact.
    try std.testing.expect(containsDecomposition(properties.first_decomposition));
    try std.testing.expect(properties.combiningClass(properties.first_combining) != 0);
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
