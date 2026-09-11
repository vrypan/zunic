//! Public-API tests for `zunic.isAscii` and `Text.isAscii`.
//!
//! `std.ascii.isAscii` checks one byte; `referenceIsAscii` below is the
//! independent whole-slice oracle these tests check the shared detector
//! against, built from that single-byte primitive rather than from
//! `zunic.isAscii` itself.
const std = @import("std");
const zunic = @import("zunic");

fn referenceIsAscii(bytes: []const u8) bool {
    for (bytes) |byte| if (!std.ascii.isAscii(byte)) return false;
    return true;
}

/// Both entry points, and the reference, must agree for `bytes`.
fn expectAgree(bytes: []const u8, expected: bool) !void {
    try std.testing.expectEqual(expected, referenceIsAscii(bytes));
    try std.testing.expectEqual(expected, zunic.isAscii(bytes));
    try std.testing.expectEqual(expected, zunic.text(bytes).isAscii());
}

test "empty input is ASCII" {
    try expectAgree("", true);
}

test "ordinary ASCII text" {
    try expectAgree("Hello, world! 123 #!@", true);
}

test "every one of the 128 ASCII byte values, alone, is ASCII" {
    var buffer: [1]u8 = undefined;
    for (0..128) |value| {
        buffer[0] = @intCast(value);
        try expectAgree(&buffer, true);
    }
}

test "every byte value 128 and above, alone, is not ASCII" {
    var buffer: [1]u8 = undefined;
    for (128..256) |value| {
        buffer[0] = @intCast(value);
        try expectAgree(&buffer, false);
    }
}

test "ASCII controls, including NUL, ESC, and DEL, count as ASCII" {
    try expectAgree("\x00", true);
    try expectAgree("\x1b", true);
    try expectAgree("\x7f", true);
    try expectAgree("a\x00b\x1bc\x7fd", true);
}

test "valid non-ASCII UTF-8 is not ASCII" {
    try expectAgree("Cafe\u{0301}", false); // combining acute
    try expectAgree("日本語", false);
    try expectAgree("👩‍👩‍👧‍👦", false);
    try expectAgree("caf\u{00E9}", false);
}

test "malformed bytes are not ASCII, same as valid non-ASCII" {
    // Any high byte disqualifies input regardless of UTF-8 validity: this
    // check does not distinguish valid from malformed non-ASCII bytes.
    try expectAgree("\xff", false);
    try expectAgree("\x80", false); // isolated continuation byte
    try expectAgree("\xc0\x80", false); // overlong NUL
    try expectAgree("\xed\xa0\x80", false); // surrogate
    try expectAgree("ok \xff trailing", false);
    try expectAgree("\xf0\x9f\x98", false); // truncated four-byte lead
}

test "high byte at every offset, across a range of lengths" {
    // Exercises vector-width boundaries and scalar tails without hardcoding
    // the host's actual SIMD width: sweeping every length up to 96 and every
    // offset within it covers whatever width `std.simd.suggestVectorLength`
    // picks, plus the boundary immediately before and after it.
    var buffer: [96]u8 = undefined;
    for (0..buffer.len) |len| {
        @memset(buffer[0..len], 'a');
        try expectAgree(buffer[0..len], true);
        for (0..len) |offset| {
            const original = buffer[offset];
            buffer[offset] = 0x80;
            try expectAgree(buffer[0..len], false);
            buffer[offset] = original;
        }
    }
}

test "varied slice alignment does not change the answer" {
    // The scanner reads from `bytes.ptr` directly; slicing a larger buffer
    // at different start offsets shifts that pointer's alignment without
    // changing content, and the answer must not depend on it.
    var buffer: [128]u8 = undefined;
    @memset(&buffer, 'x');
    buffer[100] = 0x80;
    for (0..16) |start| {
        // A slice entirely before the high byte is ASCII...
        try expectAgree(buffer[start..100], true);
        // ...one that includes it is not, regardless of where it starts.
        try expectAgree(buffer[start..101], false);
    }
}

test "escape bytes receive no special treatment" {
    // An all-ASCII SGR sequence around ASCII text is ASCII.
    try expectAgree("\x1b[31mHello\x1b[0m", true);
    // An all-ASCII, incomplete escape sequence is still ASCII.
    try expectAgree("\x1b[31", true);
    try expectAgree("\x1b]0;title", true);
    // A non-ASCII byte inside an OSC payload fails the byte-range check.
    try expectAgree("\x1b]0;caf\u{00E9}\x07", false);
    // A non-ASCII byte inside an SGR-like sequence also fails.
    try expectAgree("\x1b[3\u{00E9}mHello\x1b[0m", false);
}

test "const values and temporary views" {
    const bytes: []const u8 = "Hello";
    const text_view = zunic.text(bytes);
    try std.testing.expect(text_view.isAscii());
    // Temporary view, never bound to a local.
    try std.testing.expect(zunic.text("Hello").isAscii());
    try std.testing.expect(!zunic.text("caf\u{00E9}").isAscii());
}

test "every call re-scans: no cache across repeated calls" {
    var buffer: [4]u8 = "abcd".*;
    const view = zunic.text(&buffer);
    try std.testing.expect(view.isAscii());
    buffer[2] = 0x80;
    try std.testing.expect(!view.isAscii());
    buffer[2] = 'c';
    try std.testing.expect(view.isAscii());
}
