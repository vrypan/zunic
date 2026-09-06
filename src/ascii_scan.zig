//! Internal, bounded detection of ASCII letter-only input.
const builtin = @import("builtin");
const options = @import("build_options");

pub const Backend = enum { off, scalar, auto, simd };
pub const Paragraph = enum { none, letters, simple };
const simd_width = 16;

pub fn selectedBackend() Backend {
    return switch (options.wrap_fast_path) {
        .off => .off,
        .scalar => .scalar,
        .auto => .auto,
        .simd => .simd,
    };
}

/// Recognizes the ASCII subset whose grapheme and line-break behavior is
/// fully represented by letters, digits, apostrophes, spaces, and hard
/// separators. Over this alphabet UAX #14 places a break opportunity exactly
/// after a run of spaces, which is the rule `wrap.nextAsciiParagraph`
/// implements; `scan_test.zig` checks that exhaustively. Punctuation stays
/// out: `.` and `,` are context dependent, since `.5` is a number and takes a
/// break before it while a sentence-ending `.` does not.
/// Auto covers every architecture with a vector backend. The kernel is
/// portable @Vector code that lowers to baseline SSE2 on x86_64, and the scan
/// tests check it against the scalar path at every alignment.
pub fn paragraph(bytes: []const u8) Paragraph {
    return switch (selectedBackend()) {
        .off => .none,
        .scalar => scalarParagraph(bytes),
        .auto => if (simdSupported() and bytes.len >= simd_width) simdParagraph(bytes) else scalarParagraph(bytes),
        .simd => simdParagraph(bytes),
    };
}

fn isSimple(byte: u8) bool {
    return isLetter(byte) or (byte >= '0' and byte <= '9') or byte == ' ' or
        byte == '\'' or (byte >= 0x0A and byte <= 0x0D);
}

/// One pass that answers both questions: the letters-only case is a subset of
/// the simple case, so a separate `allLetters` sweep is not needed.
pub fn scalarParagraph(bytes: []const u8) Paragraph {
    var letters = true;
    for (bytes) |byte| {
        if (isLetter(byte)) continue;
        letters = false;
        if (!isSimple(byte)) return .none;
    }
    return if (letters) .letters else .simple;
}

pub fn simdParagraph(bytes: []const u8) Paragraph {
    if (!simdSupported()) return scalarParagraph(bytes);
    const V = @Vector(simd_width, u8);
    var letters = true;
    var index: usize = 0;
    while (index + simd_width <= bytes.len) : (index += simd_width) {
        const chunk: V = bytes[index..][0..simd_width].*;
        const lower = chunk | @as(V, @splat(0x20));
        const is_letter = (lower >= @as(V, @splat('a'))) & (lower <= @as(V, @splat('z')));
        if (@reduce(.And, is_letter)) continue;
        letters = false;
        const is_digit = (chunk >= @as(V, @splat('0'))) & (chunk <= @as(V, @splat('9')));
        const is_space = chunk == @as(V, @splat(' '));
        const is_apostrophe = chunk == @as(V, @splat('\''));
        // 0x0A..0x0D is exactly LF, VT, FF, CR.
        const is_hard = (chunk >= @as(V, @splat(0x0A))) & (chunk <= @as(V, @splat(0x0D)));
        if (!@reduce(.And, is_letter | is_digit | is_space | is_apostrophe | is_hard)) return .none;
    }
    for (bytes[index..]) |byte| {
        if (isLetter(byte)) continue;
        letters = false;
        if (!isSimple(byte)) return .none;
    }
    return if (letters) .letters else .simple;
}

pub fn scalarAllLetters(bytes: []const u8) bool {
    for (bytes) |byte| if (!isLetter(byte)) return false;
    return true;
}

pub fn simdAllLetters(bytes: []const u8) bool {
    if (!simdSupported()) return scalarAllLetters(bytes);
    var index: usize = 0;
    while (index + simd_width <= bytes.len) : (index += simd_width) {
        const chunk: @Vector(simd_width, u8) = bytes[index..][0..simd_width].*;
        const lower = chunk | @as(@Vector(simd_width, u8), @splat(0x20));
        const letters = (lower >= @as(@Vector(simd_width, u8), @splat('a'))) & (lower <= @as(@Vector(simd_width, u8), @splat('z')));
        if (!@reduce(.And, letters)) return scalarAllLetters(bytes[index..][0..simd_width]);
    }
    return scalarAllLetters(bytes[index..]);
}

pub fn simdSupported() bool {
    return switch (builtin.cpu.arch) {
        .aarch64, .x86_64 => true,
        else => false,
    };
}

fn isLetter(byte: u8) bool {
    const lower = byte | 0x20;
    return lower >= 'a' and lower <= 'z';
}
