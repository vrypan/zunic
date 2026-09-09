//! Borrowed terminal text, with a limited CSI/OSC escape scanner.
const std = @import("std");
const types = @import("types");
const escape = @import("escape.zig");
const strip = @import("strip.zig");
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
        return strip.stripAnsi(self.bytes, buffer);
    }
};

pub const Escape = struct {
    span: types.Span,
    kind: enum { sgr, other },
};

pub const Token = union(enum) {
    grapheme: types.Span,
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
            if (escape.end(self.bytes, self.pos)) |end| {
                const start = self.pos;
                self.pos = end;
                return .{ .escape = .{
                    .span = .{ .start = .{ .value = start }, .end = .{ .value = end } },
                    .kind = if (escape.isSgr(self.bytes[start..end])) .sgr else .other,
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
            if (escape.end(self.bytes, candidate) != null) {
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
