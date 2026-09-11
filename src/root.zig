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
pub const Codepoint = text_view.Codepoint;
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

/// The terminal-cell width of one code point in isolation: `0`, `1`, or `2`.
///
/// This is a flat, per-scalar lookup -- it does not group combining marks or
/// multi-scalar sequences with a base, so summing it over a string's scalars
/// is a different, narrower question than `Text.width()` and disagrees with
/// it on exactly the inputs that motivate grapheme clustering: a combining
/// mark or a conjunct's vowel sign reports its own nonzero width here, while
/// `Text.width()` folds it into the cluster it belongs to. Reach for this
/// when working with a code point that did not come from `Text`, such as one
/// produced elsewhere in a caller's own pipeline; prefer
/// `text(bytes).width()` or `text(bytes).graphemes().measured()` for text.
pub const codepointWidth = @import("tables").properties.codepointWidth;

/// One code point's classification for extended grapheme clustering
/// ([UAX #29](https://www.unicode.org/reports/tr29/)), the raw facts
/// `Text.graphemes()` applies the full boundary rules to.
pub const GraphemeClass = @import("tables").properties.GraphemeClass;

/// `Indic_Conjunct_Break`, part of the same clustering rules; also read by
/// `graphemeProperties()`.
pub const IndicConjunctBreak = @import("tables").properties.IndicConjunctBreak;

/// The three facts `graphemeProperties()` returns together, and the same
/// fields `Codepoint.grapheme` carries while iterating `codepoints()`.
pub const GraphemeProperties = @import("tables").properties.GraphemeProperties;

/// One code point's grapheme-break classification: `Grapheme_Cluster_Break`,
/// `Indic_Conjunct_Break`, and `Extended_Pictographic`.
///
/// This is the raw per-scalar data, not a boundary decision -- it does not
/// say whether a break exists between two code points, only classifies one
/// of them. `Text.graphemes()` already applies the full UAX #29 rules,
/// including the state carried between code points that a single lookup
/// cannot see, and disagreements between adjacent code points and Unicode's
/// stream-safe recommendations. Reach for this when building a different
/// segmentation on code points that did not come from `Text`, not as a
/// shortcut for clustering.
pub const graphemeProperties = @import("tables").properties.graphemeProperties;

/// Whether a code point has `East_Asian_Width` `Wide`, `Fullwidth`, or
/// `Halfwidth`.
///
/// Not the same question as `codepointWidth()`: a combining mark measures
/// zero columns even when this is `true`, and a Halfwidth scalar measures
/// one column despite it -- `codepointWidth()` only treats Wide and
/// Fullwidth as two columns. This is the raw property alone, for callers
/// that want it directly rather than folded into a width decision.
pub const isEastAsianWide = @import("tables").properties.isEastAsianWide;

/// One code point's Unicode `General_Category`: `Lu`, `Ll`, `Nd`, `Po`, and
/// so on, spelled in lowercase (`no` becomes `no_` to dodge the keyword).
pub const GeneralCategory = @import("tables").general_category.GeneralCategory;

/// `generalCategory()` plus a fixed set of `DerivedCoreProperties` booleans,
/// fetched together in one lookup. The individual `isXxx` functions below
/// each read one field of this; call this directly to avoid repeating the
/// lookup for more than one fact about the same code point.
pub const GeneralCategoryProperties = @import("tables").general_category.GeneralCategoryProperties;
pub const generalCategoryProperties = @import("tables").general_category.generalCategoryProperties;

/// One code point's `General_Category`. A flat, per-scalar lookup -- unlike
/// `codepointWidth`/`graphemeProperties`/`isEastAsianWide`, this is data
/// none of zunic's own engines read, generated solely to expose it.
pub const generalCategory = @import("tables").general_category.generalCategory;

/// `Alphabetic`: every `Lu`/`Ll`/`Lt`/`Lm`/`Lo` code point, plus some `Mn`/
/// `Mc` combining marks, every `Nl` letter-number, and even some `So`
/// symbols -- verified against every `General_Category` that actually
/// carries `Alphabetic` in the pinned data, not assumed from the property's
/// name.
pub const isAlphabetic = @import("tables").general_category.is_alphabetic;

/// `Lowercase`, per `DerivedCoreProperties`. Not the same test as
/// `generalCategory(cp) == .ll`: also true for some `Lm`/`Lo`/`Mn`/`Nl`/`So`
/// code points, verified against the pinned data.
pub const isLowercase = @import("tables").general_category.is_lowercase;

/// `Uppercase`, per `DerivedCoreProperties`. Not the same test as
/// `generalCategory(cp) == .lu`: also true for some `Nl`/`So` code points
/// (not `Lt`, despite title case reading as "uppercase-ish"), verified
/// against the pinned data.
pub const isUppercase = @import("tables").general_category.is_uppercase;

/// `Cased`: true for anything case conversion can produce or consume,
/// broader than `isUppercase(cp) or isLowercase(cp)` (also true for `Lt`
/// and code points whose case is otherwise significant).
pub const isCased = @import("tables").general_category.is_cased;

/// `Case_Ignorable`: code points a case-insensitive comparison should skip
/// over rather than compare directly, such as combining marks and some
/// punctuation. Zunic does not implement case folding; this is the raw
/// property alone.
pub const isCaseIgnorable = @import("tables").general_category.is_case_ignorable;

/// `Math`: mathematical symbols and operators. Broader than
/// `generalCategory(cp) == .sm`; also true for some `Cf`/`Ll`/`Lo`/`Lu`/
/// `Mn`/`Nd`/`Pc`/`Pd`/`Pe`/`Po`/`Ps`/`Sk`/`So` code points, verified
/// against the pinned data.
pub const isMath = @import("tables").general_category.is_math;

/// `ID_Start`: whether a code point may begin a programming-language
/// identifier under Unicode's recommended default lexical rules. Zunic
/// implements no lexer; this is the raw property for a caller building one.
pub const isIdStart = @import("tables").general_category.is_id_start;

/// `ID_Continue`: whether a code point may continue (not necessarily start)
/// an identifier under the same default rules as `isIdStart`.
pub const isIdContinue = @import("tables").general_category.is_id_continue;

/// `XID_Start`: `ID_Start` closed under Unicode normalization, so an
/// identifier built from `XID_Start`/`XID_Continue` code points stays valid
/// after NFKC. Prefer this over `isIdStart` unless a specific lexer grammar
/// calls for the unclosed property.
pub const isXidStart = @import("tables").general_category.is_xid_start;

/// `XID_Continue`, the `XID_Start` counterpart to `isIdContinue`.
pub const isXidContinue = @import("tables").general_category.is_xid_continue;

/// `Default_Ignorable_Code_Point`: code points recommended to be ignored in
/// rendering absent higher-level protocol support for them -- some format
/// characters, variation selectors, and deprecated formatting characters.
/// Zunic's own text and terminal views do not consult this property.
pub const isDefaultIgnorable = @import("tables").general_category.is_default_ignorable;

/// `Grapheme_Base`: roughly, code points that can start a grapheme cluster.
/// Distinct from `graphemeProperties(cp).gcb`, which is `Grapheme_Cluster_
/// Break`, a different (UAX #29) property Unicode maintains separately;
/// `Text.graphemes()` is built on the latter, not this one.
pub const isGraphemeBase = @import("tables").general_category.is_grapheme_base;

/// `Grapheme_Extend`, the `DerivedCoreProperties` property, not the
/// `Grapheme_Cluster_Break=Extend` class `graphemeProperties(cp).gcb` reads.
/// The two agree almost everywhere but not quite: five code points in
/// Unicode 16.0.0 differ between them. `Text.graphemes()` is built on
/// `Grapheme_Cluster_Break`, not this property.
pub const isGraphemeExtend = @import("tables").general_category.is_grapheme_extend;

/// Instrumented wrapping is retained solely for zunic's work-bound tests.
pub const testing = struct {
    pub const instrumentedIterator = wrap_engine.instrumentedIterator;
};

const std = @import("std");
pub const build_options = @import("build_options");
