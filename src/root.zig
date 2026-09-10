//! Allocation-free Unicode primitives for Zig.
//!
//! Open a view over borrowed bytes and ask it questions:
//!
//! ```zig
//! const view = zunic.text(bytes);
//! const w = view.width();
//! var it = (try view.wrap(.{ .max_columns = 80 })).iterator();
//! ```
//!
//! Byte spans and terminal-column policy form the package's public boundary.
//! Nothing allocates, and every span indexes the slice the view was opened on.
//!
//! `text` reads bytes as plain text. **Strip ANSI escape sequences before
//! using it** -- it measures them as ordinary characters, so styled input
//! reports the wrong width and can be broken mid-sequence. `terminal` offers
//! escape-aware tokens and byte-only stripping; use `text` on stripped output.
pub const utf8 = @import("encoding").utf8;
const text_view = @import("text.zig");
const text_trim = @import("text_trim.zig");
const terminal_view = @import("terminal");
const types = @import("types");
const wrap_engine = @import("layout").wrap;
pub const line_break = @import("linebreak");
const normalization = @import("normalization");

pub const ByteOffset = types.ByteOffset;
pub const Column = types.Column;
pub const Span = types.Span;
pub const MeasuredSpan = types.MeasuredSpan;
pub const Line = text_view.Line;
pub const WrapOptions = wrap_engine.Options;
pub const Overflow = wrap_engine.Overflow;
pub const Wrapped = text_view.Wrapped;
pub const Text = text_view.Text;
pub const Terminal = terminal_view.Terminal;
pub const TerminalTokens = terminal_view.Tokens;
pub const TerminalToken = terminal_view.Token;
pub const TerminalState = terminal_view.State;
pub const StyleFields = terminal_view.StyleFields;
pub const Escape = terminal_view.Escape;
pub const Terminators = text_view.Terminators;
pub const TerminatorIterator = text_view.TerminatorIterator;
pub const Graphemes = text_view.Graphemes;
pub const WordBound = text_view.WordBound;
pub const WordBounds = text_view.WordBounds;
pub const WordBoundIterator = text_view.WordBoundIterator;
pub const Form = normalization.Form;
pub const Equivalence = normalization.Equivalence;
pub const NormalizationIterator = normalization.Iterator;
pub const QuickCheck = normalization.QuickCheck;
pub const NormalizationError = normalization.Error;
pub const NormalizationWriteError = normalization.WriteError;

/// The Unicode release every table in this package is generated from.
///
/// This is the pinned *data* version. It is not zunic's package version and
/// has nothing to do with the Zig version in use. The generators' verifiers
/// assert it against the vendored UCD filenames, so an upgrade cannot leave
/// it stale.
pub const unicode_version: std.SemanticVersion = .{ .major = 16, .minor = 0, .patch = 0 };
pub const MeasuredGraphemes = text_view.MeasuredGraphemes;

/// Open a text view. Borrowed and zero-cost: no scanning happens until a
/// question is asked.
pub fn text(bytes: []const u8) Text {
    return .{ .bytes = bytes };
}

/// Open a borrowed terminal view without scanning or allocating.
/// Provides token iteration and byte-only stripping with CSI/OSC recognition.
pub fn terminal(bytes: []const u8) Terminal {
    return .{ .bytes = bytes };
}

/// Unicode 16.0.0 `White_Space=Yes`: the predicate `Text.trim()`, `trimStart()`
/// and `trimEnd()` apply at each edge, and `Text.isWhitespace(span)` applies
/// to a whole span. Not general category `Zs`, not `Pattern_White_Space`, and
/// not the zero-width set; see [trim](../docs/text/trim/README.md) for the full
/// 25-code-point table.
///
/// This scalar form is exposed for code working with a code point directly
/// rather than a span of bytes -- most span-shaped code should reach for
/// `text(bytes).isWhitespace(span)` instead, which also confirms the span is
/// exactly one such scalar rather than merely starting with one.
pub const isWhitespace = text_trim.isWhitespace;

/// Whether `glyph` is exactly one `White_Space` scalar and nothing else --
/// the primitive behind `Text.isWhitespace`, exposed directly for a byte
/// slice that did not come from a span at all. For building operations
/// `Text` and `Terminal` do not provide -- for example, a trim over
/// `terminal(bytes).tokens()` that also consults escape state, so a styled
/// space with a non-default background can be kept as content rather than
/// treated as padding -- prefer `text(bytes).isWhitespace(token.grapheme)`
/// after matching out the `.escape` case; what counts as trimmable in the
/// presence of escapes is a policy decision for that caller to make, and this
/// function and `Text.isWhitespace` only answer the Unicode question, so such
/// code does not have to re-derive `PropList.txt` to match `Text.trim()`'s
/// definition.
pub const isWhitespaceSlice = text_trim.isWhitespaceSlice;

/// Whether every byte in `bytes` is below 0x80. Empty input is ASCII, and so
/// is any ASCII control byte, including NUL, ESC, and DEL.
///
/// A plain byte-range test, not UTF-8 validation and not a printable-text
/// check: a high byte fails this whether it belongs to valid UTF-8 or to
/// malformed input. `std.ascii.isAscii` checks one byte; this checks a whole
/// slice with a vectorized scan (SIMD where the target supports it) and a
/// scalar tail. `Text.isAscii()` and `Terminal.isAscii()` are the same check
/// on a view's own bytes.
pub const isAscii = @import("encoding").ascii.isAscii;

/// Instrumented wrapping is retained solely for zunic's work-bound tests.
pub const testing = struct {
    pub const instrumentedIterator = wrap_engine.instrumentedIterator;
};

const std = @import("std");
pub const build_options = @import("build_options");
