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
//! an initial escape-aware grapheme iterator; width and wrapping are pending.
pub const utf8 = @import("encoding").utf8;
const text_view = @import("text.zig");
const terminal_view = @import("terminal.zig");
const wrap_engine = @import("layout").wrap;
pub const line_break = @import("linebreak");
const normalization = @import("normalization");

pub const ByteOffset = text_view.ByteOffset;
pub const Column = text_view.Column;
pub const Span = text_view.Span;
pub const MeasuredSpan = text_view.MeasuredSpan;
pub const Line = text_view.Line;
pub const WrapOptions = wrap_engine.Options;
pub const Overflow = wrap_engine.Overflow;
pub const Wrapped = text_view.Wrapped;
pub const Text = text_view.Text;
pub const Terminal = terminal_view.Terminal;
pub const TerminalGraphemes = terminal_view.Graphemes;
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
/// The initial API provides grapheme iteration with CSI/OSC recognition.
pub fn terminal(bytes: []const u8) Terminal {
    return .{ .bytes = bytes };
}

/// Instrumented wrapping is retained solely for zunic's work-bound tests.
pub const testing = struct {
    pub const instrumentedIterator = wrap_engine.instrumentedIterator;
};

const std = @import("std");
pub const build_options = @import("build_options");
