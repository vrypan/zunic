//! Hard line terminator views over borrowed bytes.
const Span = @import("types").Span;

/// The seven Unicode hard line terminators, as byte extents. `\r\n` is one
/// terminator of length two.
///
/// | code point | UAX #14 class |
/// | --- | --- |
/// | `U+000A` LF, `U+000D` CR | LF, CR |
/// | `U+000B` VT, `U+000C` FF | BK |
/// | `U+0085` NEL | NL |
/// | `U+2028`, `U+2029` | BK |
///
/// Scanning raw bytes is sound: no grapheme cluster spans a terminator except
/// CRLF, because CR, LF and the rest are `GCB = Control`/`CR`/`LF` and GB4/GB5
/// force a break on both sides, while GB3 keeps CRLF together and this iterator
/// emits it as one span. An ASCII terminator byte can never appear inside a
/// multi-byte sequence, since UTF-8 continuation bytes are all >= 0x80.
pub const Terminators = struct {
    bytes: []const u8,

    /// Number of terminators. `\r\n` counts as one.
    pub fn count(self: Terminators) usize {
        var it = self.iterator();
        var n: usize = 0;
        while (it.next() != null) n += 1;
        return n;
    }

    pub fn iterator(self: Terminators) TerminatorIterator {
        return .{ .bytes = self.bytes };
    }
};

pub const TerminatorIterator = struct {
    bytes: []const u8,
    pos: usize = 0,

    /// Extent of the next terminator, or null at end of input. Unlike
    /// `line_break.Iterator`, nothing is reported at end of text: only
    /// terminators physically present in the bytes.
    pub fn next(self: *TerminatorIterator) ?Span {
        while (self.pos < self.bytes.len) {
            const start = self.pos;
            const byte = self.bytes[start];
            switch (byte) {
                '\r' => {
                    const end = if (start + 1 < self.bytes.len and self.bytes[start + 1] == '\n') start + 2 else start + 1;
                    self.pos = end;
                    return .{ .start = .{ .value = start }, .end = .{ .value = end } };
                },
                0x0A, 0x0B, 0x0C => {
                    self.pos = start + 1;
                    return .{ .start = .{ .value = start }, .end = .{ .value = start + 1 } };
                },
                // U+0085 NEL is C2 85; U+2028/U+2029 are E2 80 A8/A9. Verify
                // the whole sequence: a truncated lead byte is not a terminator.
                0xC2 => {
                    if (start + 1 < self.bytes.len and self.bytes[start + 1] == 0x85) {
                        self.pos = start + 2;
                        return .{ .start = .{ .value = start }, .end = .{ .value = start + 2 } };
                    }
                    self.pos = start + 1;
                },
                0xE2 => {
                    if (start + 2 < self.bytes.len and self.bytes[start + 1] == 0x80 and
                        (self.bytes[start + 2] == 0xA8 or self.bytes[start + 2] == 0xA9))
                    {
                        self.pos = start + 3;
                        return .{ .start = .{ .value = start }, .end = .{ .value = start + 3 } };
                    }
                    self.pos = start + 1;
                },
                else => self.pos = start + 1,
            }
        }
        return null;
    }
};
