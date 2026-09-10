//! Public-API tests for `Text.trim`, `trimStart` and `trimEnd`.
//!
//! The expected whitespace set below is transcribed independently of the
//! implementation from Unicode 16.0.0 `PropList.txt`, the `White_Space`
//! property. No host-language trim or `isspace` is used as an oracle: their
//! definitions and Unicode versions differ from this one.
const std = @import("std");
const zunic = @import("zunic");

/// `White_Space=Yes`, Unicode 16.0.0 UCD `PropList.txt`.
/// https://www.unicode.org/Public/16.0.0/ucd/PropList.txt
const white_space_ranges = [_][2]u21{
    .{ 0x0009, 0x000D }, // <control-0009>..<control-000D>
    .{ 0x0020, 0x0020 }, // SPACE
    .{ 0x0085, 0x0085 }, // <control-0085>
    .{ 0x00A0, 0x00A0 }, // NO-BREAK SPACE
    .{ 0x1680, 0x1680 }, // OGHAM SPACE MARK
    .{ 0x2000, 0x200A }, // EN QUAD..HAIR SPACE
    .{ 0x2028, 0x2028 }, // LINE SEPARATOR
    .{ 0x2029, 0x2029 }, // PARAGRAPH SEPARATOR
    .{ 0x202F, 0x202F }, // NARROW NO-BREAK SPACE
    .{ 0x205F, 0x205F }, // MEDIUM MATHEMATICAL SPACE
    .{ 0x3000, 0x3000 }, // IDEOGRAPHIC SPACE
};

fn expectedWhitespace(cp: u21) bool {
    for (white_space_ranges) |range| if (cp >= range[0] and cp <= range[1]) return true;
    return false;
}

/// Every `White_Space` code point, in order, for the mixed-run tests.
const all_whitespace = blk: {
    @setEvalBranchQuota(10_000);
    var list: [25]u21 = undefined;
    var count: usize = 0;
    for (white_space_ranges) |range| {
        var cp = range[0];
        while (cp <= range[1]) : (cp += 1) {
            list[count] = cp;
            count += 1;
        }
    }
    if (count != list.len) @compileError("White_Space is 25 code points in Unicode 16.0.0");
    break :blk list;
};

fn encode(cp: u21, buffer: *[4]u8) []const u8 {
    const len = std.unicode.utf8Encode(cp, buffer) catch unreachable;
    return buffer[0..len];
}

fn concat(allocator: std.mem.Allocator, parts: []const []const u8) ![]u8 {
    return std.mem.concat(allocator, u8, parts);
}

test "the property set has exactly 25 code points" {
    var count: usize = 0;
    for (0..0x110000) |value| {
        if (expectedWhitespace(@intCast(value))) count += 1;
    }
    try std.testing.expectEqual(@as(usize, 25), count);
}

test "the exported predicate agrees with the pinned property data" {
    // zunic.isWhitespace is the same function Text.trim() uses internally;
    // this checks the public entry point directly rather than only through
    // trim() output, since that's the one downstream code actually calls.
    for (0..0x110000) |value| {
        if (value >= 0xD800 and value <= 0xDFFF) continue;
        const cp: u21 = @intCast(value);
        try std.testing.expectEqual(expectedWhitespace(cp), zunic.isWhitespace(cp));
    }
}

test "every scalar agrees with the pinned property data" {
    // Exhaustive rather than sampled: a predicate that shortcuts -- a missing
    // range, a stray one, a mask that catches a neighbour -- shows up here and
    // nowhere else. Allocation-free so the sweep stays cheap in Debug.
    var buffer: [4]u8 = undefined;
    var padded: [9]u8 = undefined;
    for (0..0x110000) |value| {
        if (value >= 0xD800 and value <= 0xDFFF) continue;
        const cp: u21 = @intCast(value);
        const encoded = encode(cp, &buffer);
        @memcpy(padded[0..encoded.len], encoded);
        padded[encoded.len] = 'x';
        @memcpy(padded[encoded.len + 1 ..][0..encoded.len], encoded);
        const whole = padded[0 .. encoded.len * 2 + 1];
        const trimmed = zunic.text(whole).trim().bytes;
        if (expectedWhitespace(cp)) {
            try std.testing.expectEqualStrings("x", trimmed);
            try std.testing.expectEqualStrings(whole[encoded.len..], zunic.text(whole).trimStart().bytes);
            try std.testing.expectEqualStrings(whole[0 .. encoded.len + 1], zunic.text(whole).trimEnd().bytes);
        } else {
            try std.testing.expectEqualStrings(whole, trimmed);
            try std.testing.expectEqualStrings(whole, zunic.text(whole).trimStart().bytes);
            try std.testing.expectEqualStrings(whole, zunic.text(whole).trimEnd().bytes);
        }
    }
}

test "each whitespace code point alone, on each edge, for each method" {
    const allocator = std.testing.allocator;
    var buffer: [4]u8 = undefined;
    for (all_whitespace) |cp| {
        const ws = encode(cp, &buffer);

        const leading = try concat(allocator, &.{ ws, "core" });
        defer allocator.free(leading);
        try std.testing.expectEqualStrings("core", zunic.text(leading).trim().bytes);
        try std.testing.expectEqualStrings("core", zunic.text(leading).trimStart().bytes);
        try std.testing.expectEqualStrings(leading, zunic.text(leading).trimEnd().bytes);

        const trailing = try concat(allocator, &.{ "core", ws });
        defer allocator.free(trailing);
        try std.testing.expectEqualStrings("core", zunic.text(trailing).trim().bytes);
        try std.testing.expectEqualStrings(trailing, zunic.text(trailing).trimStart().bytes);
        try std.testing.expectEqualStrings("core", zunic.text(trailing).trimEnd().bytes);

        const both = try concat(allocator, &.{ ws, "core", ws });
        defer allocator.free(both);
        try std.testing.expectEqualStrings("core", zunic.text(both).trim().bytes);
        try std.testing.expectEqualStrings("core" ++ "", zunic.text(both).trimStart().bytes[0 .. both.len - ws.len * 2]);
        try std.testing.expectEqualStrings(both[0 .. both.len - ws.len], zunic.text(both).trimEnd().bytes);

        // A whitespace scalar on its own is removed entirely.
        try std.testing.expectEqualStrings("", zunic.text(ws).trim().bytes);
        try std.testing.expectEqualStrings("", zunic.text(ws).trimStart().bytes);
        try std.testing.expectEqualStrings("", zunic.text(ws).trimEnd().bytes);
    }
}

test "mixed runs of every whitespace code point" {
    const allocator = std.testing.allocator;
    var run: std.ArrayList(u8) = .empty;
    defer run.deinit(allocator);
    var buffer: [4]u8 = undefined;
    for (all_whitespace) |cp| try run.appendSlice(allocator, encode(cp, &buffer));
    // Reversed too, so the end scan meets the set in the other order.
    var reversed: std.ArrayList(u8) = .empty;
    defer reversed.deinit(allocator);
    var index: usize = all_whitespace.len;
    while (index > 0) {
        index -= 1;
        try reversed.appendSlice(allocator, encode(all_whitespace[index], &buffer));
    }

    const padded = try concat(allocator, &.{ run.items, "middle here", reversed.items });
    defer allocator.free(padded);
    try std.testing.expectEqualStrings("middle here", zunic.text(padded).trim().bytes);
    try std.testing.expectEqualStrings("middle here" ++ "", zunic.text(padded).trimStart().bytes[0..11]);
    try std.testing.expectEqual(run.items.len + 11, zunic.text(padded).trimEnd().bytes.len);

    const only = try concat(allocator, &.{ run.items, reversed.items });
    defer allocator.free(only);
    try std.testing.expectEqual(@as(usize, 0), zunic.text(only).trim().bytes.len);
    try std.testing.expectEqual(@as(usize, 0), zunic.text(only).trimStart().bytes.len);
    try std.testing.expectEqual(@as(usize, 0), zunic.text(only).trimEnd().bytes.len);
}

test "empty and all-whitespace input keep their slice locations" {
    const empty = zunic.text("");
    try std.testing.expectEqual(@as(usize, 0), empty.trim().bytes.len);
    try std.testing.expectEqual(@as(usize, 0), empty.trimStart().bytes.len);
    try std.testing.expectEqual(@as(usize, 0), empty.trimEnd().bytes.len);

    const spaces = "  \t\n";
    const view = zunic.text(spaces);
    // Start-first scanning leaves `trim` and `trimStart` at the far end;
    // `trimEnd` never moves its start.
    try std.testing.expectEqual(spaces.ptr + spaces.len, view.trim().bytes.ptr);
    try std.testing.expectEqual(spaces.ptr + spaces.len, view.trimStart().bytes.ptr);
    try std.testing.expectEqual(spaces.ptr, view.trimEnd().bytes.ptr);
    try std.testing.expectEqual(@as(usize, 0), view.trim().bytes.len);
    try std.testing.expectEqual(@as(usize, 0), view.trimStart().bytes.len);
    try std.testing.expectEqual(@as(usize, 0), view.trimEnd().bytes.len);
}

test "unchanged text returns the original slice" {
    const cases = [_][]const u8{
        "a",
        "no whitespace at the edges",
        "interior  \t spaces  stay",
        "\u{200B}zero width space is not trimmed\u{200B}",
        "\u{FEFF}bom is not trimmed\u{FEFF}",
        "\u{180E}mongolian vowel separator\u{180E}",
        "\u{2060}word joiner\u{2060}",
        "\x00nul and del\x7f",
        "\u{0301}combining mark\u{0301}",
        "👩‍👩‍👧‍👦 emoji 🇬🇷",
        "日本語の文章",
        "\x1b[31mred\x1b[0m",
    };
    for (cases) |case| {
        const view = zunic.text(case);
        for ([_][]const u8{ view.trim().bytes, view.trimStart().bytes, view.trimEnd().bytes }) |result| {
            try std.testing.expectEqual(case.ptr, result.ptr);
            try std.testing.expectEqual(case.len, result.len);
        }
    }
}

test "adjacent property-range boundaries are excluded" {
    // One below and one above every range in the table.
    for (white_space_ranges) |range| {
        if (range[0] > 0) try expectNotTrimmed(range[0] - 1);
        if (range[1] < 0x10FFFF and !(range[1] + 1 >= 0xD800 and range[1] + 1 <= 0xDFFF))
            try expectNotTrimmed(range[1] + 1);
    }
}

fn expectNotTrimmed(cp: u21) !void {
    // U+2028 and U+2029 are listed as adjacent single-code-point ranges, so
    // each is the other's neighbour; only genuine non-members are checked.
    if (expectedWhitespace(cp)) return;
    var buffer: [4]u8 = undefined;
    const encoded = encode(cp, &buffer);
    var padded: [9]u8 = undefined;
    @memcpy(padded[0..encoded.len], encoded);
    padded[encoded.len] = 'x';
    @memcpy(padded[encoded.len + 1 ..][0..encoded.len], encoded);
    const whole = padded[0 .. encoded.len * 2 + 1];
    try std.testing.expectEqualStrings(whole, zunic.text(whole).trim().bytes);
}

test "ASCII shapes" {
    try std.testing.expectEqualStrings("hi", zunic.text("   hi   ").trim().bytes);
    try std.testing.expectEqualStrings("hi   ", zunic.text("   hi   ").trimStart().bytes);
    try std.testing.expectEqualStrings("   hi", zunic.text("   hi   ").trimEnd().bytes);
    try std.testing.expectEqualStrings("hi", zunic.text("\t\t hi \t").trim().bytes);
    try std.testing.expectEqualStrings("hi", zunic.text("\r\n hi \r\n").trim().bytes);
    try std.testing.expectEqualStrings("hi", zunic.text("\x0b\x0c hi \x0c\x0b").trim().bytes);
    // NUL and DEL are not White_Space and stop the scan.
    try std.testing.expectEqualStrings("\x00hi\x7f", zunic.text(" \x00hi\x7f ").trim().bytes);
}

test "typographic and ideographic spaces" {
    try std.testing.expectEqualStrings("hi", zunic.text("\u{00A0}hi\u{00A0}").trim().bytes);
    try std.testing.expectEqualStrings("hi", zunic.text("\u{202F}hi\u{202F}").trim().bytes);
    try std.testing.expectEqualStrings("hi", zunic.text("\u{2003}\u{2009}hi\u{205F}").trim().bytes);
    try std.testing.expectEqualStrings("hi", zunic.text("\u{3000}hi\u{3000}").trim().bytes);
    try std.testing.expectEqualStrings("hi", zunic.text("\u{1680}hi\u{1680}").trim().bytes);
    try std.testing.expectEqualStrings("hi", zunic.text("\u{2028}hi\u{2029}").trim().bytes);
    try std.testing.expectEqualStrings("hi", zunic.text("\u{0085}hi\u{0085}").trim().bytes);
}

test "malformed edges stop the scan and are preserved" {
    // The plan's named case: an isolated 0xFF between two spaces.
    try std.testing.expectEqualStrings("\xff", zunic.text(" \xff ").trim().bytes);
    try std.testing.expectEqualStrings("\xff ", zunic.text(" \xff ").trimStart().bytes);
    try std.testing.expectEqualStrings(" \xff", zunic.text(" \xff ").trimEnd().bytes);

    const malformed = [_][]const u8{
        "\x80", // isolated continuation byte
        "\xbf",
        "\x80\x80\x80\x80\x80\x80\x80\x80", // a long run of them
        "\xc2", // truncated two-byte
        "\xe2\x80", // truncated three-byte
        "\xf0\x9f\x98", // truncated four-byte
        "\xc0\x80", // overlong NUL
        "\xc1\xbf", // overlong
        "\xe0\x80\xa0", // overlong NBSP-shaped
        "\xc0\xa0", // overlong NBSP
        "\xed\xa0\x80", // surrogate D800
        "\xed\xbf\xbf", // surrogate DFFF
        "\xf4\x90\x80\x80", // above U+10FFFF
        "\xf5\x80\x80\x80",
        "\xff\xfe",
    };
    const allocator = std.testing.allocator;
    for (malformed) |bad| {
        const padded = try concat(allocator, &.{ " \u{3000}", bad, "\u{00A0} " });
        defer allocator.free(padded);
        try std.testing.expectEqualStrings(bad, zunic.text(padded).trim().bytes);

        const leading = try concat(allocator, &.{ bad, " " });
        defer allocator.free(leading);
        try std.testing.expectEqualStrings(bad, zunic.text(leading).trim().bytes);
        try std.testing.expectEqualStrings(leading, zunic.text(leading).trimStart().bytes);

        const trailing = try concat(allocator, &.{ " ", bad });
        defer allocator.free(trailing);
        try std.testing.expectEqualStrings(bad, zunic.text(trailing).trim().bytes);
        try std.testing.expectEqualStrings(trailing, zunic.text(trailing).trimEnd().bytes);
    }
}

test "an overlong or truncated encoding is never mistaken for whitespace" {
    // \xe0\x80\xa0 is an overlong U+0020; \xc0\xa0 an overlong NBSP. Neither
    // may be trimmed, and neither may hide the valid space beside it.
    try std.testing.expectEqualStrings("\xe0\x80\xa0", zunic.text(" \xe0\x80\xa0 ").trim().bytes);
    try std.testing.expectEqualStrings("\xc0\xa0", zunic.text(" \xc0\xa0 ").trim().bytes);
    // The backward scan must not decode the trailing bytes of a valid
    // four-byte scalar as a scalar of their own.
    try std.testing.expectEqualStrings("a\u{1F600}", zunic.text("a\u{1F600} ").trim().bytes);
    // A truncated four-byte lead followed by real whitespace: the whitespace
    // goes, the malformed lead stays.
    try std.testing.expectEqualStrings("\xf0", zunic.text("\xf0\u{3000}").trim().bytes);
    try std.testing.expectEqualStrings("\xf0", zunic.text("\xf0\u{3000}").trimEnd().bytes);
}

test "edges are independent across a malformed middle" {
    const input = " \u{00A0}left \xff\xc0\x80 right\u{2003} ";
    const trimmed = zunic.text(input).trim().bytes;
    try std.testing.expectEqualStrings("left \xff\xc0\x80 right", trimmed);
    // The middle was neither validated nor repaired.
    try std.testing.expectError(error.InvalidUtf8, zunic.text(trimmed).validate());
    // Malformed bytes at one end do not block the other.
    try std.testing.expectEqualStrings("\xff bytes", zunic.text("\xff bytes ").trim().bytes);
    try std.testing.expectEqualStrings("bytes \xff", zunic.text(" bytes \xff").trim().bytes);
}

test "code points, not graphemes" {
    // A leading space followed by a combining mark: the space goes, the mark
    // stays, even though the two form one cluster for grapheme purposes.
    const input = " \u{0301}x";
    try std.testing.expectEqualStrings("\u{0301}x", zunic.text(input).trim().bytes);
    try std.testing.expectEqualStrings("\u{0301}x", zunic.text(input).trimStart().bytes);
    // The same at the end.
    try std.testing.expectEqualStrings("x \u{0301}", zunic.text("x \u{0301} ").trim().bytes);
}

test "escapes receive no special treatment" {
    const input = "  \x1b[31mred\x1b[0m  ";
    try std.testing.expectEqualStrings("\x1b[31mred\x1b[0m", zunic.text(input).trim().bytes);
    // ESC itself ends a scan.
    try std.testing.expectEqualStrings("\x1b", zunic.text(" \x1b ").trim().bytes);
    // Stripping first, then trimming, is the supported order for styled text.
    var buffer: [32]u8 = undefined;
    const plain = try zunic.terminal(input).stripAnsi(&buffer);
    try std.testing.expectEqualStrings("red", zunic.text(plain).trim().bytes);
}

test "idempotence and composition" {
    const inputs = [_][]const u8{
        "  hi  ",
        "\u{3000}\u{00A0}hi\u{2009}\t",
        " \xff ",
        "   ",
        "",
        "x",
    };
    for (inputs) |input| {
        const view = zunic.text(input);
        const once = view.trim();
        try std.testing.expectEqualStrings(once.bytes, once.trim().bytes);
        try std.testing.expectEqualStrings(once.bytes, once.trimStart().bytes);
        try std.testing.expectEqualStrings(once.bytes, once.trimEnd().bytes);
        // trimStart then trimEnd equals trim, and so does the other order.
        try std.testing.expectEqualStrings(once.bytes, view.trimStart().trimEnd().bytes);
        try std.testing.expectEqualStrings(once.bytes, view.trimEnd().trimStart().bytes);
    }
}

test "backing storage is unchanged and slices point into it" {
    var storage = " \u{00A0}hello \n".*;
    const before = storage;
    const view = zunic.text(&storage);
    const trimmed = view.trim();
    try std.testing.expectEqualStrings("hello", trimmed.bytes);
    try std.testing.expectEqualSlices(u8, &before, &storage);
    try std.testing.expectEqual(storage[3..].ptr, trimmed.bytes.ptr);
    try std.testing.expectEqual(@as(usize, 5), trimmed.bytes.len);
}

test "substring inputs trim within their own bounds" {
    const whole = "prefix \u{2003} middle \u{2003} suffix";
    const inner = whole[7..18];
    try std.testing.expectEqualStrings("\u{2003} middle ", inner);
    try std.testing.expectEqualStrings("middle", zunic.text(inner).trim().bytes);
    // Offsets from the trimmed view are relative to the trimmed bytes.
    const trimmed = zunic.text(inner).trim();
    var it = trimmed.graphemes().iterator();
    const first = it.next().?;
    try std.testing.expectEqual(@as(usize, 0), first.start.value);
    try std.testing.expectEqualStrings("m", trimmed.bytes[first.start.value..first.end.value]);
}

test "offsets from later iteration index the returned view" {
    const input = "\u{00A0} Hello, \u{4E16}\u{754C}! \n";
    const trimmed = zunic.text(input).trim();
    try std.testing.expectEqualStrings("Hello, \u{4E16}\u{754C}!", trimmed.bytes);

    var graphemes = trimmed.graphemes().iterator();
    var clusters: usize = 0;
    var last_end: usize = 0;
    while (graphemes.next()) |span| {
        try std.testing.expectEqual(last_end, span.start.value);
        last_end = span.end.value;
        clusters += 1;
    }
    try std.testing.expectEqual(trimmed.bytes.len, last_end);
    try std.testing.expectEqual(@as(usize, 10), clusters);

    var words = trimmed.wordBounds().iterator();
    const hello = words.next().?;
    try std.testing.expect(hello.is_word);
    try std.testing.expectEqualStrings("Hello", trimmed.bytes[hello.start.value..hello.end.value]);
}

test "chaining with width, wrapping and normalization" {
    const input = "  cafe\u{0301} \u{3000}";
    const trimmed = zunic.text(input).trim();
    try std.testing.expectEqualStrings("cafe\u{0301}", trimmed.bytes);
    try std.testing.expectEqual(@as(usize, 4), trimmed.width());
    try std.testing.expect(try trimmed.eql("caf\u{00E9}", .canonical));

    var buffer: [16]u8 = undefined;
    try std.testing.expectEqualStrings("caf\u{00E9}", try trimmed.normalize(.nfc).writeTo(&buffer));

    const wrapped = try zunic.text("  alpha beta gamma  ").trim().wrap(.{ .max_columns = 10 });
    try std.testing.expectEqual(@as(usize, 2), wrapped.count());
}

test "an already-trimmed large input is not scanned through its middle" {
    const allocator = std.testing.allocator;
    const body = try allocator.alloc(u8, 1 << 16);
    defer allocator.free(body);
    @memset(body, 'a');
    const view = zunic.text(body);
    try std.testing.expectEqual(body.ptr, view.trim().bytes.ptr);
    try std.testing.expectEqual(body.len, view.trim().bytes.len);

    const padded = try concat(allocator, &.{ "  \u{3000}", body, "\u{00A0}\t" });
    defer allocator.free(padded);
    try std.testing.expectEqual(body.len, zunic.text(padded).trim().bytes.len);
}

test "isWhitespaceSlice requires the whole slice to be exactly one scalar" {
    try std.testing.expect(zunic.isWhitespaceSlice(" "));
    try std.testing.expect(zunic.isWhitespaceSlice("\u{3000}"));
    try std.testing.expect(zunic.isWhitespaceSlice("\u{00A0}"));
    try std.testing.expect(!zunic.isWhitespaceSlice(""));
    try std.testing.expect(!zunic.isWhitespaceSlice("x"));
    // Starts with whitespace but is not only whitespace: a leading space
    // plus a combining mark is two scalars, matching Text.trim()'s
    // code-points-not-graphemes contract.
    try std.testing.expect(!zunic.isWhitespaceSlice(" \u{0301}"));
    try std.testing.expect(!zunic.isWhitespaceSlice("  "));
    // A whitespace scalar's bytes with a trailing byte appended: no longer
    // exactly one scalar's worth of bytes.
    try std.testing.expect(!zunic.isWhitespaceSlice("\u{3000}x"));
    // Malformed and overlong encodings never qualify.
    try std.testing.expect(!zunic.isWhitespaceSlice("\xff"));
    try std.testing.expect(!zunic.isWhitespaceSlice("\xc0\xa0")); // overlong NBSP
    try std.testing.expect(!zunic.isWhitespaceSlice("\xc2")); // truncated
}

test "Text.isWhitespace over real grapheme spans" {
    const bytes = "a \u{3000}\u{0301}";
    const view = zunic.text(bytes);
    var it = view.graphemes().iterator();

    const a = it.next().?;
    try std.testing.expectEqualStrings("a", bytes[a.start.value..a.end.value]);
    try std.testing.expect(!view.isWhitespace(a));

    const space = it.next().?;
    try std.testing.expectEqualStrings(" ", bytes[space.start.value..space.end.value]);
    try std.testing.expect(view.isWhitespace(space));

    // U+3000 followed by a combining mark is one grapheme cluster (the mark
    // attaches to the ideographic space), so the whole span is two scalars
    // and is correctly not reported as whitespace, matching isWhitespaceSlice.
    const combined = it.next().?;
    try std.testing.expectEqualStrings("\u{3000}\u{0301}", bytes[combined.start.value..combined.end.value]);
    try std.testing.expect(!view.isWhitespace(combined));

    try std.testing.expect(it.next() == null);
}

test "Text.isWhitespace agrees for Span and MeasuredSpan" {
    const bytes = "x \u{00A0}y";
    const view = zunic.text(bytes);
    var plain = view.graphemes().iterator();
    var measured = view.graphemes().measured().iterator();
    while (plain.next()) |span| {
        const measured_span = measured.next().?;
        try std.testing.expectEqual(view.isWhitespace(span), view.isWhitespace(measured_span));
    }
    try std.testing.expect(measured.next() == null);
}

test "Text.isWhitespace on non-grapheme spans" {
    // Every single-scalar UAX #14 hard terminator is also White_Space, so
    // its Terminators span answers true -- except CRLF, the one terminator
    // that is two scalars (CR then LF), which like any other two-scalar
    // span answers false even though both scalars are individually
    // White_Space.
    const with_terms = "a\r\nb\u{2028}c\x0Cd";
    const terms_view = zunic.text(with_terms);
    var terms = terms_view.terminators().iterator();
    const crlf = terms.next().?;
    try std.testing.expectEqualStrings("\r\n", with_terms[crlf.start.value..crlf.end.value]);
    try std.testing.expect(!terms_view.isWhitespace(crlf));
    const ls = terms.next().?;
    try std.testing.expect(terms_view.isWhitespace(ls));
    const ff = terms.next().?;
    try std.testing.expectEqualStrings("\x0C", with_terms[ff.start.value..ff.end.value]);
    try std.testing.expect(terms_view.isWhitespace(ff));
    try std.testing.expect(terms.next() == null);

    // A TerminalToken's escape span starts with ESC, which is not
    // White_Space, so it answers false.
    const styled = "\x1b[31mx";
    var tokens = zunic.terminal(styled).tokens().iterator();
    const escape = (try tokens.next()).?.escape;
    try std.testing.expect(!zunic.text(styled).isWhitespace(escape.span));
}
