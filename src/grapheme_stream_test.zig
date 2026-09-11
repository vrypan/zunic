const std = @import("std");
const zunic = @import("zunic");

const fixture = @embedFile("data/GraphemeBreakTest-17.0.0.txt");

test "streaming decisions match every Unicode grapheme fixture" {
    var lines = std.mem.splitScalar(u8, fixture, '\n');
    while (lines.next()) |raw_line| {
        const line = raw_line[0 .. std.mem.indexOfScalar(u8, raw_line, '#') orelse raw_line.len];
        if (std.mem.trim(u8, line, " \t\r").len == 0) continue;
        var cps: [64]u21 = undefined;
        var breaks: [65]bool = undefined;
        var cp_len: usize = 0;
        var break_len: usize = 0;
        var tokens = std.mem.tokenizeAny(u8, line, " \t\r");
        while (tokens.next()) |token| {
            if (std.mem.eql(u8, token, "÷") or std.mem.eql(u8, token, "×")) {
                breaks[break_len] = std.mem.eql(u8, token, "÷");
                break_len += 1;
            } else {
                cps[cp_len] = try std.fmt.parseInt(u21, token, 16);
                cp_len += 1;
            }
        }
        try std.testing.expectEqual(cp_len + 1, break_len);
        if (cp_len < 2) continue;
        var state: zunic.GraphemeState = .{};
        for (1..cp_len) |i|
            try std.testing.expectEqual(breaks[i], zunic.graphemeBreak(cps[i - 1], cps[i], &state));

        // Any prefix state is a valid chunk boundary: resume from every split
        // and require the remaining decisions to be identical.
        for (1..cp_len) |split| {
            var prefix: zunic.GraphemeState = .{};
            for (1..split) |i| _ = zunic.graphemeBreak(cps[i - 1], cps[i], &prefix);
            const checkpoint = prefix;
            for (split..cp_len) |i|
                try std.testing.expectEqual(breaks[i], zunic.graphemeBreak(cps[i - 1], cps[i], &prefix));
            prefix = checkpoint;
            for (split..cp_len) |i|
                try std.testing.expectEqual(breaks[i], zunic.graphemeBreak(cps[i - 1], cps[i], &prefix));
        }
    }
}

test "stream state supports replay checkpoints and resets on boundaries" {
    var state: zunic.GraphemeState = .{};
    try std.testing.expect(!zunic.graphemeBreak('a', 0x0301, &state));
    const checkpoint = state;
    try std.testing.expect(zunic.graphemeBreak(0x0301, 'b', &state));
    state = checkpoint;
    try std.testing.expect(!zunic.graphemeBreak(0x0301, 0x0308, &state));

    var replay: zunic.GraphemeState = .{};
    const cps = [_]u21{ 'a', 0x0301, 'b', 0x0308 };
    const expected = [_]bool{ false, true, false };
    for (expected, 1..) |want, i|
        try std.testing.expectEqual(want, zunic.graphemeBreak(cps[i - 1], cps[i], &replay));
}

test "out-of-range values form independent boundaries" {
    var state: zunic.GraphemeState = .{};
    try std.testing.expect(!zunic.graphemeBreak('a', 0x0301, &state));
    try std.testing.expect(zunic.graphemeBreak(0x0301, 0x110000, &state));
    try std.testing.expect(zunic.graphemeBreak(0x110000, 'b', &state));
    try std.testing.expect(!zunic.graphemeBreak('b', 0x0308, &state));
}

test "surrogate code points use the default other classification" {
    var state: zunic.GraphemeState = .{};
    try std.testing.expect(zunic.graphemeBreak('a', 0xd800, &state));
    try std.testing.expect(!zunic.graphemeBreak(0xd800, 0x0308, &state));
}

test "streaming state covers contextual UAX 29 rules" {
    // Regional indicators pair from the start of each cluster.
    var regional: zunic.GraphemeState = .{};
    try std.testing.expect(!zunic.graphemeBreak(0x1f1e6, 0x1f1e7, &regional));
    try std.testing.expect(zunic.graphemeBreak(0x1f1e7, 0x1f1e8, &regional));

    // A repeated ZWJ does not extend GB11's EP Extend* ZWJ context.
    var zwj: zunic.GraphemeState = .{};
    try std.testing.expect(!zunic.graphemeBreak(0x1f600, 0x200d, &zwj));
    try std.testing.expect(!zunic.graphemeBreak(0x200d, 0x200d, &zwj));
    try std.testing.expect(zunic.graphemeBreak(0x200d, 0x1f600, &zwj));

    // Default UAX #29 treats emoji modifiers as Extend. Ghostty may tailor
    // this pair; the standard streaming API deliberately does not.
    var modifier: zunic.GraphemeState = .{};
    try std.testing.expect(!zunic.graphemeBreak('"', 0x1f3ff, &modifier));

    // Indic_Conjunct_Break preserves a consonant-linker-consonant cluster.
    var indic: zunic.GraphemeState = .{};
    try std.testing.expect(!zunic.graphemeBreak(0x0915, 0x094d, &indic));
    try std.testing.expect(!zunic.graphemeBreak(0x094d, 0x0915, &indic));

    // Controls use the default rules, including the CR x LF exception.
    var controls: zunic.GraphemeState = .{};
    try std.testing.expect(zunic.graphemeBreak('a', '\r', &controls));
    try std.testing.expect(!zunic.graphemeBreak('\r', '\n', &controls));
    try std.testing.expect(zunic.graphemeBreak('\n', 'b', &controls));
}

test "empty and singleton whole-slice inputs need no pairwise call" {
    var empty = zunic.text("").graphemes().iterator();
    try std.testing.expect(empty.next() == null);
    var singleton = zunic.text("a").graphemes().iterator();
    const only = singleton.next().?;
    try std.testing.expectEqual(@as(usize, 0), only.start.value);
    try std.testing.expectEqual(@as(usize, 1), only.end.value);
    try std.testing.expect(singleton.next() == null);
}

test "streaming decisions match whole-slice iteration on random streams" {
    var prng = std.Random.DefaultPrng.init(0x031_17_29);
    const random = prng.random();
    const alphabet = [_]u21{
        'a',     'b',     0x000d, 0x000a, 0x0301, 0x0600,  0x0903,  0x0915,
        0x094d,  0x1100,  0x1161, 0x11a8, 0x200d, 0x1f1e6, 0x1f1e7, 0x1f3fb,
        0x1f44d, 0x1f600,
    };
    var cps: [64]u21 = undefined;
    var offsets: [65]usize = undefined;
    var bytes: [256]u8 = undefined;

    for (0..2_000) |_| {
        const count = 2 + random.uintLessThan(usize, cps.len - 1);
        var len: usize = 0;
        for (0..count) |i| {
            offsets[i] = len;
            cps[i] = alphabet[random.uintLessThan(usize, alphabet.len)];
            len += std.unicode.utf8Encode(cps[i], bytes[len..]) catch unreachable;
        }
        offsets[count] = len;

        var spans = zunic.text(bytes[0..len]).graphemes().iterator();
        _ = spans.next().?;
        var next = spans.next();
        var state: zunic.GraphemeState = .{};
        for (1..count) |i| {
            const want = next != null and next.?.start.value == offsets[i];
            try std.testing.expectEqual(want, zunic.graphemeBreak(cps[i - 1], cps[i], &state));
            if (want) next = spans.next();
        }
        try std.testing.expect(next == null);
    }
}
