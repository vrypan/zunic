//! Public, question-shaped views over a borrowed UTF-8 byte slice.
//!
//! Offsets returned by the text view are always relative to the slice used to
//! open it. The view never allocates, and opening it does no scanning.
const std = @import("std");
const grapheme_engine = @import("segmentation").grapheme;
const width_engine = @import("layout").width;
const normalization = @import("normalization");
const word_engine = @import("segmentation").word;
const wrap_engine = @import("layout").wrap;
const text_trim = @import("text_trim.zig");
const ascii_scan = @import("encoding").ascii;
const scalar_engine = @import("encoding").scalar;
const properties = @import("tables").properties;

const types = @import("types");
pub const ByteOffset = types.ByteOffset;
pub const Column = types.Column;
pub const Span = types.Span;
pub const MeasuredSpan = types.MeasuredSpan;

pub const Graphemes = struct {
    bytes: []const u8,

    pub fn iterator(self: Graphemes) Iterator(false) {
        return .{ .inner = grapheme_engine.iterator(self.bytes) };
    }

    pub fn measured(self: Graphemes) MeasuredGraphemes {
        return .{ .bytes = self.bytes };
    }
};

pub const MeasuredGraphemes = struct {
    bytes: []const u8,

    pub fn iterator(self: MeasuredGraphemes) Iterator(true) {
        return .{ .inner = grapheme_engine.iterator(self.bytes) };
    }
};

pub fn Iterator(comptime include_measure: bool) type {
    return struct {
        inner: grapheme_engine.Iterator,

        // Complete the decoder-to-consumer inline chain. Otherwise the larger
        // engine can cause this wrapper to be outlined once per grapheme;
        // unmeasured callers also need to eliminate the unused width work.
        pub inline fn next(self: *@This()) ?if (include_measure) MeasuredSpan else Span {
            const span = self.inner.next() orelse return null;
            if (!include_measure) return .{
                .start = .{ .value = span.start },
                .end = .{ .value = span.end },
            };
            // The grapheme engine already measured this cluster while it
            // segmented it, so both fields are decoded from that measure
            // rather than recomputed: re-measuring the same bytes would
            // decode and classify every scalar of the cluster a second time.
            return .{
                .start = .{ .value = span.start },
                .end = .{ .value = span.end },
                .columns = @intCast(grapheme_engine.displayColumns(span.columns)),
                .renderable = grapheme_engine.isRenderable(span.columns),
            };
        }
    };
}

pub const Line = struct {
    start: ByteOffset,
    end: ByteOffset,
    columns: Column,
};

pub const Wrapped = struct {
    bytes: []const u8,
    options: wrap_engine.Options,

    pub fn count(self: Wrapped) usize {
        var it = self.iterator();
        var result: usize = 0;
        while (it.next() != null) result += 1;
        return result;
    }

    /// `Text.wrap` is the supported way to obtain a `Wrapped`, and it rejects
    /// a zero column limit, so the engine's only error cannot arise through
    /// that route.
    ///
    /// This struct has public fields, though, so one can also be built by
    /// hand with `max_columns = 0`. `catch unreachable` would make that
    /// undefined behaviour in a build with safety off, which is a poor answer
    /// for a value the caller is allowed to construct: narrow it to the
    /// smallest legal width instead, so the worst case is an unhelpful
    /// wrapping rather than a corrupt one.
    pub fn iterator(self: Wrapped) WrappedIterator {
        const options: wrap_engine.Options = .{
            .max_columns = @max(1, self.options.max_columns),
            .overflow = self.options.overflow,
        };
        return .{ .inner = wrap_engine.iterator(self.bytes, options) catch unreachable };
    }
};

pub const WrappedIterator = struct {
    inner: wrap_engine.Iterator,

    pub fn next(self: *WrappedIterator) ?Line {
        const line = self.inner.next() orelse return null;
        return .{
            .start = .{ .value = line.start },
            .end = .{ .value = line.end },
            .columns = .{ .value = line.columns },
        };
    }
};

/// A borrowed view of bytes read as plain text: every byte is content, and
/// terminal control sequences are not recognised.
///
/// If the bytes may contain ANSI escape sequences, strip them first. This view
/// measures `ESC`, `[`, `3`, `1`, `m` as ordinary characters, so
/// `"\x1b[31mred\x1b[0m"` reports width 10 rather than 3 and wrapping can
/// place a break inside the sequence, which corrupts the output. The initial
/// `terminal` view provides tokens and stripAnsi() for escape handling; this
/// text view makes no attempt at interpreting escapes.
pub const Text = struct {
    bytes: []const u8,

    /// Check that the complete byte slice is valid UTF-8.
    ///
    /// This is a direct UTF-8 scan. It does not iterate graphemes or look up
    /// Unicode properties. Other text operations remain tolerant of malformed
    /// input whether or not this method is called.
    pub fn validate(self: Text) error{InvalidUtf8}!void {
        if (!std.unicode.utf8ValidateSlice(self.bytes)) return error.InvalidUtf8;
    }

    /// Whether every byte is below 0x80. Empty input is ASCII, and so is any
    /// ASCII control byte, including NUL, ESC, and DEL. A high byte fails
    /// this whether it belongs to valid UTF-8 or to malformed input -- this
    /// is a byte-range test, not UTF-8 validation. Scans the whole slice
    /// every call; there is no cache.
    pub fn isAscii(self: Text) bool {
        return ascii_scan.isAscii(self.bytes);
    }

    /// Extended grapheme clusters. Call `.measured()` on the result for
    /// per-cluster terminal columns.
    pub fn graphemes(self: Text) Graphemes {
        return .{ .bytes = self.bytes };
    }

    /// Individual Unicode scalars, one at a time. See `Codepoints` for how
    /// this differs from `graphemes()` and how malformed UTF-8 is reported.
    pub fn codepoints(self: Text) Codepoints {
        return .{ .bytes = self.bytes };
    }

    /// Total terminal columns, after the same filtering `measured()` applies:
    /// control characters and undecodable bytes occupy none.
    pub fn width(self: Text) usize {
        return width_engine.textWidth(self.bytes);
    }

    /// Hard line terminators, as byte extents. Paragraph content is the gaps
    /// between them; see the module docs.
    pub fn terminators(self: Text) Terminators {
        return .{ .bytes = self.bytes };
    }

    /// Default UAX #29 word boundaries, as a partition of the bytes.
    pub fn wordBounds(self: Text) WordBounds {
        return .{ .bytes = self.bytes };
    }

    /// The scalars of this text in `form`, as a lazy iterator.
    ///
    /// Borrows the input without scanning it. Produces new scalars rather
    /// than spans into the input.
    pub fn normalize(self: Text, comptime form: normalization.Form) normalization.Iterator(form) {
        return normalization.normalize(self.bytes, form);
    }

    /// A safe output byte capacity for normalization in `form`.
    /// Uses only the input length, without scanning or validating the bytes.
    /// Returns Overflow if the bound cannot fit in usize.
    pub fn normalizedLenBound(self: Text, comptime form: normalization.Form) error{Overflow}!usize {
        return normalization.normalizedLenBound(self.bytes.len, form);
    }

    /// Whether these bytes and `other` are equivalent under `how`.
    ///
    /// `.canonical`: the same text, however it happens to be encoded.
    /// `"caf\u{00E9}"` and `"cafe\u{0301}"` are equal; `"\u{FB01}"` and `"fi"`
    /// are not, being compatibility-equivalent only -- ask with
    /// `.compatibility` for that broader, lossier relation instead.
    ///
    /// Decided in lockstep without normalizing either side into a buffer, so
    /// it allocates nothing: each equivalence is form-independent within
    /// itself (`NFD(a) == NFD(b)` exactly when `NFC(a) == NFC(b)`, and
    /// likewise for `NFKD`/`NFKC`), which is why `how` selects a relation and
    /// not a normalization form.
    pub fn eql(self: Text, other: []const u8, comptime how: normalization.Equivalence) normalization.Error!bool {
        return normalization.eql(self.bytes, other, how);
    }

    /// Whether these bytes are already in `form`.
    ///
    /// Short-circuits on a decisive `false`, so it is not a whole-input
    /// validator; a `true` answer does mean the whole input was examined.
    /// `NFC_QC` is tri-valued and a Maybe costs real work to settle, so an
    /// input full of composable marks is slower than one that is plainly
    /// already normalized.
    pub fn isNormalized(self: Text, comptime form: normalization.Form) normalization.Error!bool {
        return normalization.isNormalized(self.bytes, form);
    }

    /// The UAX #15 quick check: `yes`, `no`, or `maybe`.
    ///
    /// Cheaper than `isNormalized`, and weaker in two ways worth knowing.
    /// `maybe` is a real answer, not a failure -- it means the question needs
    /// context this scan does not gather. And it does not enforce zunic's
    /// configured combining-run limit, so `yes` does not promise that
    /// `normalize` will accept the input.
    ///
    /// Unlike `isNormalized` it always reads the whole slice, so malformed
    /// UTF-8 after a decisive `no` is still reported.
    pub fn isNormalizedQuick(self: Text, comptime form: normalization.Form) error{InvalidUtf8}!normalization.QuickCheck {
        return normalization.isNormalizedQuick(self.bytes, form);
    }

    /// This text without Unicode whitespace at either end.
    ///
    /// The result borrows the same storage, so keep it alive and unchanged.
    /// Offsets from the returned view are relative to *its* bytes, not to the
    /// untrimmed input.
    ///
    /// Whitespace is Unicode 16.0.0 `White_Space`, all 25 code points of it:
    /// U+0009..U+000D, U+0020, U+0085, U+00A0, U+1680, U+2000..U+200A,
    /// U+2028, U+2029, U+202F, U+205F and U+3000. No-break spaces are
    /// trimmed; U+200B, U+FEFF, U+2060, NUL and DEL are not.
    ///
    /// Trimming works on code points, not graphemes: a leading space followed
    /// by a combining mark loses the space and keeps the mark. Escape bytes
    /// get no special treatment, so an `ESC` ends a scan like any other
    /// content.
    ///
    /// Malformed UTF-8 ends a scan without an error, and the two ends are
    /// independent, so `" \xff "` trims to `"\xff"`. Interior bytes are never
    /// examined. Call `validate()` when strict input is required.
    pub fn trim(self: Text) Text {
        const rest = self.bytes[text_trim.startIndex(self.bytes)..];
        if (rest.len == 0) return .{ .bytes = rest };
        return .{ .bytes = rest[0..text_trim.endIndex(rest)] };
    }

    /// This text without leading Unicode whitespace. The far end is not
    /// inspected. See `trim` for the whitespace set and the borrowing rules.
    pub fn trimStart(self: Text) Text {
        return .{ .bytes = self.bytes[text_trim.startIndex(self.bytes)..] };
    }

    /// This text without trailing Unicode whitespace. Scanning starts at the
    /// end, never from the beginning. See `trim` for the whitespace set and
    /// the borrowing rules.
    pub fn trimEnd(self: Text) Text {
        return .{ .bytes = self.bytes[0..text_trim.endIndex(self.bytes)] };
    }

    /// Whether `span` (a `Span`, `MeasuredSpan`, or anything else with
    /// `start`/`end` byte offsets) is exactly one Unicode 16.0.0
    /// `White_Space` scalar within this text -- not a span that merely
    /// starts with one. `span` is assumed to index `self.bytes`; a span from
    /// a different byte slice gives a meaningless answer rather than an
    /// error.
    ///
    /// This is the same definition `trim()` uses, extended to a span you
    /// already have -- while iterating `graphemes()`, for example, or a
    /// `TerminalToken`'s `.grapheme` field. Correct, if not always an
    /// interesting question, for a span that was never grapheme content:
    /// every single-scalar UAX #14 hard terminator (LF, VT, FF, CR, NEL, LS,
    /// PS) is also `White_Space`, so its `Terminators` span answers `true`
    /// -- except CRLF, the one terminator that is two scalars, which like
    /// any other two-scalar span answers `false`. An escape sequence's
    /// leading `ESC` byte is not `White_Space`, so a `TerminalToken`'s
    /// `Escape.span` answers `false`.
    pub fn isWhitespace(self: Text, span: anytype) bool {
        return text_trim.isWhitespaceSlice(self.bytes[span.start.value..span.end.value]);
    }

    /// Greedy display lines within a finite column limit.
    pub fn wrap(self: Text, options: wrap_engine.Options) error{InvalidWidth}!Wrapped {
        if (options.max_columns == 0) return error.InvalidWidth;
        return .{ .bytes = self.bytes, .options = options };
    }
};

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

/// One segment of the UAX #29 word partition.
pub const WordBound = struct {
    start: ByteOffset,
    end: ByteOffset,
    /// True when at least one scalar in the segment is `Alphabetic` or has
    /// general category `Nd`, `Nl` or `No`.
    ///
    /// This is a zunic convenience, not a UAX #29 rule, and not a claim that
    /// the segment is a linguistic word. It cannot be read off `Word_Break`:
    /// `U+4E00` is `WB=Other` and Alphabetic, `U+00B2` is `WB=Other` and
    /// `GC=No`, and among combining marks `U+0345` is Alphabetic while
    /// `U+0308` is not.
    is_word: bool,
};

/// The default, locale-independent word boundaries of
/// [UAX #29 revision 45](https://www.unicode.org/reports/tr29/tr29-45.html#Word_Boundaries),
/// pinned to Unicode 16.0.0.
///
/// The segments partition the input: the first starts at zero, each one starts
/// where the previous ended, and the last ends at `bytes.len`. Punctuation and
/// whitespace are segments too, flagged `is_word = false`, and adjacent
/// non-word segments are not merged. Empty input yields nothing.
///
/// These are *default* boundaries. They do not do dictionary segmentation, so
/// they do not find words in Thai, Lao, Khmer, Myanmar, Chinese or Japanese
/// text; that needs tailoring this package does not provide. The limitation is
/// broader than UAX #14's SA caveat.
///
/// ```zig
/// var it = zunic.text(line).wordBounds().iterator();
/// while (it.next()) |segment| {
///     if (segment.is_word) use(line[segment.start.value..segment.end.value]);
/// }
/// ```
pub const WordBounds = struct {
    bytes: []const u8,

    pub fn iterator(self: WordBounds) WordBoundIterator {
        return .{ .inner = word_engine.iterator(self.bytes) };
    }
};

pub const WordBoundIterator = struct {
    inner: word_engine.Iterator,

    pub fn next(self: *WordBoundIterator) ?WordBound {
        const span = self.inner.next() orelse return null;
        return .{
            .start = .{ .value = span.start },
            .end = .{ .value = span.end },
            .is_word = span.is_word,
        };
    }
};

/// One decoded Unicode scalar, or one byte of malformed input.
pub const Codepoint = struct {
    start: ByteOffset,
    end: ByteOffset,
    /// Null for a byte that could not begin or continue valid UTF-8; `end`
    /// still advances by exactly one byte in that case, the same recovery
    /// `graphemes()` and `width()` use, so scanning always finishes.
    value: ?u21,
    /// This scalar's own terminal-cell width, `0`, `1`, or `2` -- the same
    /// flat lookup as the top-level `codepointWidth()`, not folded into a
    /// cluster. Malformed input (`value == null`) is `0`, matching
    /// `Text.width()`'s own treatment of undecodable bytes. Summing this
    /// field over every item is not the same question as `Text.width()`;
    /// see `codepointWidth()`'s docs for why.
    width: u2,
    /// This scalar's raw grapheme-break classification -- the same lookup
    /// `graphemeProperties()` performs, and the facts `graphemes()` clusters
    /// with, not a cluster boundary decision by itself. Use this to build a
    /// different segmentation than `graphemes()` provides; `graphemes()`
    /// already applies the full UAX #29 rules for the common case.
    grapheme: properties.GraphemeProperties,
    /// Whether this scalar has `East_Asian_Width` `Wide`, `Fullwidth`, or
    /// `Halfwidth` -- the same lookup as the top-level `isEastAsianWide()`.
    /// Not the same question as `width`: a combining mark (general category
    /// `Mn`/`Me`/`Cf`) measures zero columns even when this is `true`, and a
    /// Halfwidth scalar measures one column despite it, since `width` only
    /// treats Wide and Fullwidth as two columns. `east_asian_wide` is
    /// `false`, not `0`, for malformed input.
    east_asian_wide: bool,
};

/// The individual Unicode scalars of this text, as a lazy iterator.
///
/// Unlike `graphemes()`, this does not group combining marks or multi-scalar
/// sequences with their base -- each scalar is its own item. Malformed UTF-8
/// is never an error here: see `Codepoint.value`.
///
/// ```zig
/// var it = zunic.text(bytes).codepoints().iterator();
/// while (it.next()) |cp| if (cp.value) |scalar| use(scalar);
/// ```
pub const Codepoints = struct {
    bytes: []const u8,

    pub fn iterator(self: Codepoints) CodepointIterator {
        return .{ .inner = scalar_engine.iterator(self.bytes) };
    }
};

pub const CodepointIterator = struct {
    inner: scalar_engine.Iterator,

    pub fn next(self: *CodepointIterator) ?Codepoint {
        const token = self.inner.next() orelse return null;
        return .{
            .start = .{ .value = token.start },
            .end = .{ .value = token.end },
            .value = token.codepoint,
            .width = token.cell_width,
            .grapheme = token.grapheme,
            .east_asian_wide = token.east_asian_wide,
        };
    }
};
