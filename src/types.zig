//! Shared public byte positions and display measurements.
//!
//! The one dependency, `text_trim`'s whitespace predicate, is for
//! `Span.isWhitespace` and `MeasuredSpan.isWhitespace` alone -- both types
//! stay plain data otherwise, and nothing here does grapheme segmentation,
//! width classification, or any other engine work.
const text_trim = @import("text_trim");

pub const ByteOffset = struct {
    value: usize,
};

pub const Column = struct {
    value: usize,
};

pub const Span = struct {
    start: ByteOffset,
    end: ByteOffset,

    /// Whether `bytes[self.start.value..self.end.value]` is exactly one
    /// Unicode 16.0.0 `White_Space` scalar -- the same definition
    /// `Text.trim()` uses. `bytes` must be the slice this span was produced
    /// from (or another slice with the same content at these offsets); a
    /// `Span` carries no reference to its bytes on its own.
    ///
    /// Correct, if not always an interesting question, for a span that was
    /// never grapheme content: every single-scalar UAX #14 hard terminator
    /// (LF, VT, FF, CR, NEL, LS, PS) is also `White_Space`, so its
    /// `Terminators` span answers `true` -- except CRLF, the one terminator
    /// that is two scalars, which like any other two-scalar span answers
    /// `false`. An escape sequence's leading `ESC` byte is not `White_Space`,
    /// so a `TerminalToken`'s `Escape.span` answers `false`.
    pub fn isWhitespace(self: Span, bytes: []const u8) bool {
        return text_trim.isWhitespaceSlice(bytes[self.start.value..self.end.value]);
    }
};

pub const MeasuredSpan = struct {
    start: ByteOffset,
    end: ByteOffset,
    columns: u2,
    renderable: bool,

    /// See `Span.isWhitespace`; the same check over a measured grapheme span.
    pub fn isWhitespace(self: MeasuredSpan, bytes: []const u8) bool {
        return text_trim.isWhitespaceSlice(bytes[self.start.value..self.end.value]);
    }
};
