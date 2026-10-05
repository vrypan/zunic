//! Strict Unicode scalar iteration over borrowed UTF-8 bytes.
const utf8 = @import("encoding").utf8;
const CodepointView = @import("cp").CodepointView;

/// The individual Unicode scalars of this text, as a lazy iterator.
/// Each yielded item is the same view returned by zunic.cp(value), with property
/// lookups deferred until requested. No allocation or eager property lookup.
///
/// Iteration stops at the first malformed UTF-8 sequence. After next() returns
/// null, inspect the iterator's err field to distinguish failure from exhaustion.
/// Unlike graphemes(), this does not group combining marks with their base.
///
/// ```zig
/// var it = zunic.text(bytes).codepoints().iterator();
/// while (it.next()) |point| use(point.value);
/// if (it.err) |err| handleDecodeError(err, it.offset);
/// ```
pub const Codepoints = struct {
    bytes: []const u8,

    pub fn iterator(self: Codepoints) CodepointIterator {
        return .{ .bytes = self.bytes };
    }
};

pub const DecodeError = enum { invalid_utf8 };

/// Strict UTF-8 iteration. A copy is an independent checkpoint over borrowed bytes.
pub const CodepointIterator = struct {
    bytes: []const u8,
    /// Byte offset of the next scalar, or of the undecodable sequence on error.
    /// Equals bytes.len after normal exhaustion. Relative to the view's slice.
    offset: usize = 0,
    /// Sticky decoding failure. Null means no error has been encountered;
    /// only a loop that reaches exhaustion has checked the complete input.
    err: ?DecodeError = null,

    /// Return a valid scalar view, or null on exhaustion or decoding failure.
    /// On failure the offending bytes are not consumed. Subsequent calls keep
    /// returning null and preserve err and offset.
    pub fn next(self: *CodepointIterator) ?CodepointView {
        if (self.err != null or self.offset == self.bytes.len) return null;
        const step = utf8.step(self.bytes[self.offset..]);
        const value = step.cp orelse {
            self.err = .invalid_utf8;
            return null;
        };
        self.offset += step.len;
        return .{ .value = value };
    }
};
