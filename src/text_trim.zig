//! Edge scanning for Unicode whitespace trimming.
//!
//! `startIndex` and `endIndex` are private helpers behind `Text.trim`,
//! `Text.trimStart` and `Text.trimEnd`. They return retained byte indices
//! into the slice they were given and touch only the bytes they remove plus
//! a bounded look at the first retained scalar, so an already-trimmed input
//! is never scanned through its middle.
//!
//! `isWhitespace` and `isWhitespaceSlice` are shared beyond this file: the
//! former as `zunic.isWhitespace`, the latter backing `Span.isWhitespace` and
//! `MeasuredSpan.isWhitespace` in `src/types.zig` as well as
//! `zunic.isWhitespaceSlice` directly. See their doc comments at those call
//! sites for what each is for.
//!
//! The only dependency is the tolerant UTF-8 decoder. Grapheme, word, width,
//! normalization and line-break engines answer other questions, and the fused
//! property record carries no `White_Space` bit; a 25-code-point set is
//! cheaper to test directly than to look up.
const utf8 = @import("encoding").utf8;

/// Unicode 16.0.0 `White_Space=Yes`, as published in UCD `PropList.txt`.
///
/// Exactly 25 code points. This is not general category `Zs`, not
/// `Pattern_White_Space`, not the zero-width set, and not the UAX #14 hard
/// terminators: U+00A0 and U+202F are trimmed although they are no-break, and
/// U+200B, U+FEFF, U+180E and U+2060 are not trimmed although they render as
/// nothing.
pub fn isWhitespace(cp: u21) bool {
    return switch (cp) {
        0x0009...0x000D,
        0x0020,
        0x0085,
        0x00A0,
        0x1680,
        0x2000...0x200A,
        0x2028,
        0x2029,
        0x202F,
        0x205F,
        0x3000,
        => true,
        else => false,
    };
}

/// True for the ASCII members of the set, so the common case answers without
/// decoding. Every other ASCII byte ends a scan.
inline fn isAsciiWhitespace(byte: u8) bool {
    return byte == ' ' or (byte >= 0x09 and byte <= 0x0D);
}

/// Whether `glyph` is exactly one `White_Space` scalar -- not a slice that
/// merely starts or ends with one. A grapheme cluster or other span can be
/// more than one scalar (a space plus a combining mark, say), and this is
/// what tells those apart from an actual whitespace-only span: the decode
/// must consume the whole slice, not just its first scalar.
pub fn isWhitespaceSlice(glyph: []const u8) bool {
    const decoded = utf8.step(glyph);
    return decoded.len == glyph.len and decoded.cp != null and isWhitespace(decoded.cp.?);
}

/// Index of the first byte to retain: the offset of the first scalar that is
/// neither whitespace nor decodable, or `bytes.len` if every scalar is
/// whitespace.
pub fn startIndex(bytes: []const u8) usize {
    var pos: usize = 0;
    while (pos < bytes.len) {
        const byte = bytes[pos];
        if (byte < 0x80) {
            if (!isAsciiWhitespace(byte)) return pos;
            pos += 1;
            continue;
        }
        const decoded = utf8.step(bytes[pos..]);
        const cp = decoded.cp orelse return pos;
        if (!isWhitespace(cp)) return pos;
        pos += decoded.len;
    }
    return pos;
}

/// Index one past the last byte to retain, or `0` if every scalar is
/// whitespace.
///
/// Non-ASCII needs a candidate lead byte found by walking back a bounded
/// distance and re-decoding forward, because reading continuation bytes
/// backwards cannot tell a well-formed sequence from the tail of a malformed
/// one. Each candidate must decode to exactly the bytes between it and the
/// current end, so a suffix of a longer sequence is rejected rather than
/// mistaken for a scalar of its own. Four bytes is the whole search: no UTF-8
/// sequence is longer, and every scalar in the set fits in three.
pub fn endIndex(bytes: []const u8) usize {
    var end: usize = bytes.len;
    scan: while (end > 0) {
        const byte = bytes[end - 1];
        if (byte < 0x80) {
            if (!isAsciiWhitespace(byte)) return end;
            end -= 1;
            continue;
        }
        var len: usize = 2;
        while (len <= 4 and len <= end) : (len += 1) {
            const candidate = end - len;
            const decoded = utf8.step(bytes[candidate..end]);
            if (decoded.len != len) continue;
            const cp = decoded.cp orelse continue;
            if (!isWhitespace(cp)) return end;
            end = candidate;
            continue :scan;
        }
        return end;
    }
    return end;
}
