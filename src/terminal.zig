//! Borrowed terminal text, with a limited CSI/OSC escape scanner.
const std = @import("std");
const text = @import("text.zig");
const scalar = @import("encoding").scalar;
const grapheme = @import("segmentation").grapheme;

pub const Terminal = struct {
    bytes: []const u8,

    /// Content and recognized escape commands in their original order.
    pub fn tokens(self: Terminal) Tokens {
        return .{ .bytes = self.bytes };
    }

    /// Remove recognized CSI/OSC sequences into caller-owned storage.
    /// Copies all other bytes unchanged, without decoding or validating UTF-8.
    /// Returns the written prefix, with no NUL terminator. On NoSpace, the
    /// output prefix remains written and may end inside a UTF-8 sequence.
    /// Use separate storage, or a buffer starting at the same address as input.
    pub fn stripAnsi(self: Terminal, buffer: []u8) error{NoSpace}![]u8 {
        var read: usize = 0;
        var written: usize = 0;
        scan: while (read < self.bytes.len) {
            if (escapeEnd(self.bytes, read)) |end| {
                read = end;
                continue;
            }
            // Unroll the short prefix so dense commands do not pay for a
            // vector search or a per-byte run counter. A failed ESC is content.
            inline for (0..16) |index| {
                if (read == self.bytes.len) return buffer[0..written];
                if (index != 0 and self.bytes[read] == 0x1b) continue :scan;
                if (written == buffer.len) return error.NoSpace;
                buffer[written] = self.bytes[read];
                written += 1;
                read += 1;
            }
            // Longer runs use Zig's SIMD-capable search and a bulk copy.
            const end = std.mem.findScalarPos(u8, self.bytes, read, 0x1b) orelse self.bytes.len;
            const count = @min(end - read, buffer.len - written);
            std.mem.copyForwards(u8, buffer[written..][0..count], self.bytes[read..][0..count]);
            written += count;
            if (count < end - read) return error.NoSpace;
            read = end;
        }
        return buffer[0..written];
    }
};

pub const Escape = struct {
    span: text.Span,
    kind: enum { sgr, other },
};

pub const Token = union(enum) {
    grapheme: text.Span,
    escape: Escape,
};

pub const Tokens = struct {
    bytes: []const u8,

    pub fn iterator(self: Tokens) TokenIterator {
        return .{ .bytes = self.bytes };
    }
};

pub const TokenIterator = struct {
    bytes: []const u8,
    pos: usize = 0,
    run_start: usize = 0,
    inner: grapheme.Iterator = .{ .bytes = "" },
    before_escape: ?grapheme.TableState = null,
    failed: bool = false,

    /// Returns tokens without checking content beyond an escape. If later
    /// content joins the preceding grapheme, latches EscapeInsideGrapheme.
    /// Already returned content and commands are not retracted.
    pub fn next(self: *TokenIterator) error{EscapeInsideGrapheme}!?Token {
        if (self.failed) return error.EscapeInsideGrapheme;
        if (self.inner.pos == self.inner.bytes.len) {
            if (self.pos == self.bytes.len) return null;
            if (escapeEnd(self.bytes, self.pos)) |end| {
                const start = self.pos;
                self.pos = end;
                return .{ .escape = .{
                    .span = .{ .start = .{ .value = start }, .end = .{ .value = end } },
                    .kind = if (isSgr(self.bytes[start..end])) .sgr else .other,
                } };
            }
            if (self.before_escape) |saved| {
                var state = saved;
                if (!state.step(grapheme.categoryOf(scalar.at(self.bytes, self.pos)))) {
                    self.failed = true;
                    return error.EscapeInsideGrapheme;
                }
                self.before_escape = null;
            }
            self.openRun();
        }
        const span = self.inner.next().?;
        if (span.end == self.inner.bytes.len and self.pos < self.bytes.len) {
            // Save only the final grapheme's state. No content beyond the
            // escape is read until a later next() call reaches it.
            const first = scalar.at(self.inner.bytes, span.start);
            var state = grapheme.TableState.init(grapheme.categoryOf(first));
            var offset = first.end;
            while (offset < span.end) {
                const token = scalar.at(self.inner.bytes, offset);
                _ = state.step(grapheme.categoryOf(token));
                offset = token.end;
            }
            self.before_escape = state;
        }
        return .{ .grapheme = .{
            .start = .{ .value = self.run_start + span.start },
            .end = .{ .value = self.run_start + span.end },
        } };
    }

    fn openRun(self: *TokenIterator) void {
        self.run_start = self.pos;
        var search = self.pos;
        while (std.mem.indexOfScalarPos(u8, self.bytes, search, 0x1b)) |candidate| {
            if (escapeEnd(self.bytes, candidate) != null) {
                self.pos = candidate;
                self.inner = grapheme.iterator(self.bytes[self.run_start..self.pos]);
                return;
            }
            search = candidate + 1;
        }
        self.pos = self.bytes.len;
        self.inner = grapheme.iterator(self.bytes[self.run_start..]);
    }
};

fn isSgr(bytes: []const u8) bool {
    if (bytes[1] != '[' or bytes[bytes.len - 1] != 'm') return false;
    for (bytes[2 .. bytes.len - 1]) |byte| {
        if (!(byte >= '0' and byte <= '9') and byte != ';' and byte != ':') return false;
    }
    return true;
}

// Recognize only complete 7-bit CSI and OSC sequences. Unsupported or broken
// sequences fall back to ordinary text. An unexpected ESC aborts recognition,
// so repeated unterminated introducers cannot cause quadratic rescanning.
inline fn escapeEnd(bytes: []const u8, start: usize) ?usize {
    if (bytes[start] != 0x1b or bytes.len - start < 2) return null;
    var pos = start + 2;
    switch (bytes[start + 1]) {
        '[' => {
            while (pos < bytes.len and bytes[pos] >= 0x30 and bytes[pos] <= 0x3f) : (pos += 1) {}
            while (pos < bytes.len and bytes[pos] >= 0x20 and bytes[pos] <= 0x2f) : (pos += 1) {}
            if (pos < bytes.len and bytes[pos] >= 0x40 and bytes[pos] <= 0x7e) return pos + 1;
            return null;
        },
        ']' => {
            while (pos < bytes.len) : (pos += 1) {
                const byte = bytes[pos];
                if (byte == 0x07) return pos + 1;
                if (byte == 0x1b) {
                    if (bytes.len - pos >= 2 and bytes[pos + 1] == '\\') return pos + 2;
                    return null;
                }
                // This first draft accepts printable payload bytes (including
                // UTF-8), not embedded C0 controls or DEL.
                if (byte < 0x20 or byte == 0x7f) return null;
            }
            return null;
        },
        else => return null,
    }
}
