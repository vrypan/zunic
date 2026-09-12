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
//! `text` reads bytes as plain text. ANSI escape sequences are ordinary bytes
//! here, so remove them before measuring or wrapping styled input.
pub const utf8 = @import("encoding").utf8;
const codepoint_view = @import("cp");
const text_view = @import("text");
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
pub const Terminators = text_view.Terminators;
pub const TerminatorIterator = text_view.TerminatorIterator;
pub const Graphemes = text_view.Graphemes;
pub const WordBound = text_view.WordBound;
pub const WordBounds = text_view.WordBounds;
pub const WordBoundIterator = text_view.WordBoundIterator;
/// The code-point iterator yields the same view as cp(value).
pub const Codepoint = CodepointView;
pub const DecodeError = text_view.DecodeError;
pub const Codepoints = text_view.Codepoints;
pub const CodepointIterator = text_view.CodepointIterator;
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
pub const unicode_version: std.SemanticVersion = .{ .major = 17, .minor = 0, .patch = 0 };
/// Largest code point in the Unicode codespace. `u21` can represent larger
/// integers, so callers accepting arbitrary `u21` values can guard with this.
pub const max_codepoint: u21 = 0x10ffff;
pub const MeasuredGraphemes = text_view.MeasuredGraphemes;

/// Open a text view. Borrowed and zero-cost: no scanning happens until a
/// question is asked.
pub const text = text_view.init;

/// Open a code-point view without decoding or looking up any properties.
pub const cp = codepoint_view.init;

pub const CodepointView = codepoint_view.CodepointView;
pub const GeneralProperties = codepoint_view.GeneralProperties;

/// Whether `glyph` is exactly one `White_Space` scalar and nothing else --
/// the primitive behind `Text.isWhitespace`, exposed directly for a byte
/// slice that did not come from a span at all. It answers only the Unicode
/// question; callers decide how whitespace participates in their own higher
/// level protocols.
pub const isWhitespaceSlice = text_view.isWhitespaceSlice;

/// Whether every byte in `bytes` is below 0x80. Empty input is ASCII, and so
/// is any ASCII control byte, including NUL, ESC, and DEL.
///
/// A plain byte-range test, not UTF-8 validation and not a printable-text
/// check: a high byte fails this whether it belongs to valid UTF-8 or to
/// malformed input. `std.ascii.isAscii` checks one byte; this checks a whole
/// slice with a vectorized scan (SIMD where the target supports it) and a
/// scalar tail. `Text.isAscii()` is the same check on its view's bytes.
pub const isAscii = @import("encoding").ascii.isAscii;

/// One code point's classification for extended grapheme clustering
/// ([UAX #29](https://www.unicode.org/reports/tr29/)), the raw facts
/// `Text.graphemes()` applies the full boundary rules to.
pub const GraphemeClass = @import("tables").properties.GraphemeClass;

/// `Indic_Conjunct_Break`, part of the same clustering rules; also read by
/// `CodepointView.grapheme()`.
pub const IndicConjunctBreak = @import("tables").properties.IndicConjunctBreak;

/// The three facts `CodepointView.grapheme()` returns together, and the same
/// fields `Codepoint.grapheme()` returns while iterating `codepoints()`.
pub const GraphemeProperties = codepoint_view.GraphemeProperties;

/// The six values of Unicode's `East_Asian_Width` property.
pub const EastAsianWidth = @import("tables").terminal_properties.EastAsianWidth;

/// All terminal-facing scalar properties stored in the terminal table,
/// fetched together with one indexed lookup. The fields have the same
/// semantics and wider-`u21` fallback as the CodepointView methods.
pub const TerminalProperties = codepoint_view.TerminalProperties;

pub const CaseFold = codepoint_view.CaseFold;
pub const Decomposition = codepoint_view.Decomposition;
pub const DecompositionType = codepoint_view.DecompositionType;
pub const Numeric = codepoint_view.Numeric;
pub const NumericType = codepoint_view.NumericType;

/// Copyable state for incremental default UAX #29 grapheme decisions.
pub const GraphemeState = @import("segmentation").stream.GraphemeState;
/// Report whether a grapheme boundary occurs before `current` and advance the
/// incremental state. See `GraphemeState` and the API documentation for the
/// adjacent-pair calling protocol.
pub const graphemeBreak = @import("segmentation").stream.graphemeBreak;

/// One code point's Unicode `General_Category`: `Lu`, `Ll`, `Nd`, `Po`, and
/// so on, spelled in lowercase (`no` becomes `no_` to dodge the keyword).
pub const GeneralCategory = @import("tables").general_category.GeneralCategory;

/// Instrumented wrapping is retained solely for zunic's work-bound tests.
pub const testing = struct {
    pub const instrumentedIterator = wrap_engine.instrumentedIterator;
};

const std = @import("std");
pub const build_options = @import("build_options");
