//! Borrowed terminal text, with a limited CSI/OSC escape scanner.
const std = @import("std");
const text = @import("text.zig");
const scalar = @import("encoding").scalar;
const grapheme = @import("segmentation").grapheme;

pub const Terminal = struct {
    bytes: []const u8,

    /// Extended graphemes with complete supported escapes between clusters.
    /// The iterator rejects escapes inside a cluster with EscapeInsideGrapheme.
    /// This does not emulate cursor movement or track active formatting.
    pub fn graphemes(self: Terminal) Graphemes {
        return .{ .bytes = self.bytes };
    }
};

pub const Graphemes = struct {
    bytes: []const u8,

    pub fn iterator(self: Graphemes) Iterator {
        return .{ .bytes = self.bytes };
    }
};

pub const Iterator = struct {
    bytes: []const u8,
    pos: usize = 0,
    run_start: usize = 0,
    inner: grapheme.Iterator = .{ .bytes = "" },
    failed: bool = false,

    /// Returns contiguous content spans, excluding recognized escapes.
    /// An escape inside a grapheme is an error, reported before that grapheme
    /// is returned. Subsequent calls repeat the error.
    pub fn next(self: *Iterator) error{EscapeInsideGrapheme}!?text.Span {
        if (self.failed) return error.EscapeInsideGrapheme;
        if (self.inner.pos == self.inner.bytes.len and !self.openRun()) return null;
        const span = self.inner.next().?;
        if (span.end == self.inner.bytes.len) {
            const after = self.skipEscapes(self.pos);
            if (after < self.bytes.len) {
                // Only the final grapheme before escapes needs an extra check.
                // Replay its state rather than changing the plain-text engine
                // or adding escape handling to its hot loop.
                const first = scalar.at(self.inner.bytes, span.start);
                var state = grapheme.TableState.init(grapheme.categoryOf(first));
                var offset = first.end;
                while (offset < span.end) {
                    const token = scalar.at(self.inner.bytes, offset);
                    _ = state.step(grapheme.categoryOf(token));
                    offset = token.end;
                }
                if (!state.step(grapheme.categoryOf(scalar.at(self.bytes, after)))) {
                    self.failed = true;
                    return error.EscapeInsideGrapheme;
                }
            }
            self.pos = after;
        }
        return .{
            .start = .{ .value = self.run_start + span.start },
            .end = .{ .value = self.run_start + span.end },
        };
    }

    fn skipEscapes(self: *const Iterator, from: usize) usize {
        var pos = from;
        while (pos < self.bytes.len) {
            pos = escapeEnd(self.bytes, pos) orelse break;
        }
        return pos;
    }

    fn openRun(self: *Iterator) bool {
        self.run_start = self.skipEscapes(self.pos);
        self.pos = self.run_start;
        if (self.pos == self.bytes.len) return false;
        var search = self.pos;
        while (std.mem.indexOfScalarPos(u8, self.bytes, search, 0x1b)) |candidate| {
            if (escapeEnd(self.bytes, candidate) != null) {
                self.pos = candidate;
                self.inner = grapheme.iterator(self.bytes[self.run_start..self.pos]);
                return true;
            }
            search = candidate + 1;
        }
        self.pos = self.bytes.len;
        self.inner = grapheme.iterator(self.bytes[self.run_start..]);
        return true;
    }
};

// Recognize only complete 7-bit CSI and OSC sequences. Unsupported or broken
// sequences fall back to ordinary text. An unexpected ESC aborts recognition,
// so repeated unterminated introducers cannot cause quadratic rescanning.
fn escapeEnd(bytes: []const u8, start: usize) ?usize {
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
