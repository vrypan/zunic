//! Internal, bounded detection of ASCII letter-only input.
const std = @import("std");
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
/// reproduced by `wrap.nextAsciiParagraph`: a break opportunity after a run
/// of spaces, suppressed before an infix separator that does not begin a
/// number. `wrap_exhaustive_test.zig` checks that against the real rules.
///
/// Excluded on purpose, each because it creates an opportunity this rule does
/// not model: `-` (BA breaks after), `!` `?` (EX), `/` (SY), `(` `)` (OP/CP),
/// and `$` `%` `+` (PO/PR number contexts).
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
    return switch (byte) {
        'a'...'z', 'A'...'Z', '0'...'9', ' ' => true,
        0x0A...0x0D => true,
        '"', '#', '&', '\'', '*', ',', '.', ':', ';', '=', '@', '_' => true,
        else => false,
    };
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
        const is_space = chunk == @as(V, @splat(' '));
        // Letters and spaces are the overwhelmingly common mix, so settle it
        // before building the punctuation masks below.
        if (@reduce(.And, is_letter | is_space)) continue;
        const is_digit = (chunk >= @as(V, @splat('0'))) & (chunk <= @as(V, @splat('9')));
        // 0x0A..0x0D is exactly LF, VT, FF, CR.
        const is_hard = (chunk >= @as(V, @splat(0x0A))) & (chunk <= @as(V, @splat(0x0D)));
        // The accepted punctuation, as ranges where the bytes are adjacent:
        // 0x22..0x23 is `"#`, 0x26..0x27 is `&'`, 0x3A..0x3B is `:;`.
        const q1 = (chunk >= @as(V, @splat(0x22))) & (chunk <= @as(V, @splat(0x23)));
        const q2 = (chunk >= @as(V, @splat(0x26))) & (chunk <= @as(V, @splat(0x27)));
        const q3 = (chunk >= @as(V, @splat(0x3A))) & (chunk <= @as(V, @splat(0x3B)));
        const q4 = chunk == @as(V, @splat('*'));
        const q5 = chunk == @as(V, @splat(','));
        const q6 = chunk == @as(V, @splat('.'));
        const q7 = chunk == @as(V, @splat('='));
        const q8 = chunk == @as(V, @splat('@'));
        const q9 = chunk == @as(V, @splat('_'));
        const punct = q1 | q2 | q3 | q4 | q5 | q6 | q7 | q8 | q9;
        if (!@reduce(.And, is_letter | is_digit | is_space | is_hard | punct)) return .none;
    }
    for (bytes[index..]) |byte| {
        if (isLetter(byte)) continue;
        letters = false;
        if (!isSimple(byte)) return .none;
    }
    return if (letters) .letters else .simple;
}

/// Returns whether every byte is printable ASCII (0x20..0x7E). Every such
/// byte is its own extended grapheme cluster of width 1, so text made only of
/// them measures exactly its own length. Controls, DEL, and anything above
/// ASCII are excluded: they either measure zero or can combine with a
/// neighbour, so they fall back to the general path.
pub fn allPrintable(bytes: []const u8) bool {
    return switch (selectedBackend()) {
        .off => false,
        .scalar => scalarAllPrintable(bytes),
        .auto => if (simdSupported() and bytes.len >= simd_width) simdAllPrintable(bytes) else scalarAllPrintable(bytes),
        .simd => simdAllPrintable(bytes),
    };
}

pub fn scalarAllPrintable(bytes: []const u8) bool {
    for (bytes) |byte| if (byte < 0x20 or byte > 0x7E) return false;
    return true;
}

pub fn simdAllPrintable(bytes: []const u8) bool {
    if (!simdSupported()) return scalarAllPrintable(bytes);
    const V = @Vector(simd_width, u8);
    var index: usize = 0;
    while (index + simd_width <= bytes.len) : (index += simd_width) {
        const chunk: V = bytes[index..][0..simd_width].*;
        const printable = (chunk >= @as(V, @splat(0x20))) & (chunk <= @as(V, @splat(0x7E)));
        if (!@reduce(.And, printable)) return false;
    }
    return scalarAllPrintable(bytes[index..]);
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

/// One line's worth of ASCII, measured without deciding where it could break.
///
/// `columns` counts printable bytes: every ASCII byte is its own cluster, and
/// `0x00..0x1F` are zero-width, so the count is exact rather than a bound.
/// `end` is the first byte of the hard terminator, or the slice end.
pub const AsciiLine = struct {
    end: usize,
    columns: usize,
    /// Bytes to skip to reach the next line: the terminator's length, `0` at
    /// end of input. CRLF is one terminator of two bytes.
    terminator_len: usize,
};

/// Measure the run at `start` up to the next hard terminator, or null when a
/// byte outside `0x00..0x7E` appears before one.
///
/// The null is the caller's signal to fall back: DEL and everything above it
/// need the general path, DEL because it is zero-width and the rest because
/// they are not ASCII at all. A `>` against `0x7E` settles both at once.
///
/// This deliberately answers only "how wide is this line", not "where may it
/// break". A line that fits needs no break opportunity, so it needs none of
/// the alphabet restrictions `isSimple` imposes -- which is what lets source
/// code take this path when it cannot take `paragraph`'s.
pub fn asciiLine(bytes: []const u8, start: usize) ?AsciiLine {
    var pos = start;
    var columns: usize = 0;
    if (selectedBackend() != .off and simdSupported()) {
        const V = @Vector(simd_width, u8);
        const Mask = std.meta.Int(.unsigned, simd_width);
        while (pos + simd_width <= bytes.len) : (pos += simd_width) {
            const chunk: V = bytes[pos..][0..simd_width].*;
            // Anything that ends the run, in one mask: a byte the policy
            // cannot answer (`> 0x7E` covers DEL and non-ASCII alike) or a
            // hard terminator (the contiguous 0x0A..0x0D).
            //
            // Both leave the chunk to the scalar loop rather than deciding
            // here, because which comes *first* changes the answer: a
            // terminator ahead of a non-ASCII byte yields a line, the other
            // order yields null. A whole-chunk reduce cannot see the order.
            const ends_run = (chunk > @as(V, @splat(0x7E))) |
                ((chunk >= @as(V, @splat(0x0A))) & (chunk <= @as(V, @splat(0x0D))));
            if (@reduce(.Or, ends_run)) break;
            const printable = chunk >= @as(V, @splat(0x20));
            columns += @popCount(@as(Mask, @bitCast(printable)));
        }
    }
    while (pos < bytes.len) : (pos += 1) {
        const byte = bytes[pos];
        if (byte > 0x7E) return null;
        if (byte >= 0x0A and byte <= 0x0D) {
            const crlf = byte == '\r' and pos + 1 < bytes.len and bytes[pos + 1] == '\n';
            return .{ .end = pos, .columns = columns, .terminator_len = if (crlf) 2 else 1 };
        }
        if (byte >= 0x20) columns += 1;
    }
    return .{ .end = bytes.len, .columns = columns, .terminator_len = 0 };
}
