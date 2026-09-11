//! Lightweight code-point view. Construction stores the value without looking up data.
const tables = @import("tables");
const folding = @import("case_folding.zig");

/// A decoded code point. No allocation, decoding, or eager property lookup.
/// Accepts every u21; each operation retains its documented wider-input fallback.
pub const CodepointView = packed struct(u32) {
    value: u21,
    // A full-width backing integer avoids the i21/i24 memory round-trip
    // emitted for an ordinary struct by Zig 0.16. Keep construction register-only.
    _padding: u11 = 0,

    /// General_Category and DerivedCoreProperties, fetched together.
    pub fn general(self: CodepointView) GeneralProperties {
        return @bitCast(tables.general_category.generalCategoryProperties(self.value));
    }

    /// East Asian width, emoji flags, and terminal width facts, fetched together.
    pub fn terminal(self: CodepointView) TerminalProperties {
        return @bitCast(tables.terminal_properties.terminalProperties(self.value));
    }

    /// Raw UAX #29 classification, not a boundary decision. Use Text.graphemes()
    /// or graphemeBreak() to apply the stateful segmentation rules.
    pub fn grapheme(self: CodepointView) GraphemeProperties {
        return @bitCast(tables.properties.graphemeProperties(self.value));
    }

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
    pub fn width(self: CodepointView) u2 {
        return tables.properties.codepointWidth(self.value);
    }

    /// Whether a code point has `East_Asian_Width` `Wide`, `Fullwidth`, or
    /// `Halfwidth`.
    ///
    /// Not the same question as `CodepointView.width()`: a combining mark measures
    /// zero columns even when this is `true`, and a Halfwidth scalar measures
    /// one column despite it -- `CodepointView.width()` only treats Wide and
    /// Fullwidth as two columns. This is the raw property alone, for callers
    /// that want it directly rather than folded into a width decision.
    pub fn isEastAsianWide(self: CodepointView) bool {
        return tables.properties.isEastAsianWide(self.value);
    }

    /// Unicode 17.0.0 `White_Space=Yes`: the predicate `Text.trim()`, `trimStart()`
    /// and `trimEnd()` apply at each edge, and `Text.isWhitespace(span)` applies
    /// to a whole span. Not general category `Zs`, not `Pattern_White_Space`, and
    /// not the zero-width set; see [trim](../docs/text/trim/README.md) for the full
    /// 25-code-point table.
    ///
    /// This scalar form is exposed for code working with a code point directly
    /// rather than a span of bytes -- most span-shaped code should reach for
    /// `text(bytes).isWhitespace(span)` instead, which also confirms the span is
    /// exactly one such scalar rather than merely starting with one.
    pub fn isWhitespace(self: CodepointView) bool {
        return @import("text_trim.zig").isWhitespace(self.value);
    }

    /// Full default C/F mapping; excludes Turkic alternatives. Unmapped and
    /// out-of-range values map to themselves. The result owns its fixed buffer.
    pub fn fullCaseFold(self: CodepointView) folding.CaseFold {
        return folding.fullCaseFold(self.value);
    }
};

/// General_Category and DerivedCoreProperties in one packed record.
/// Values above 0x10FFFF have category cn and all flags false.
pub const GeneralProperties = packed struct(u32) {
    category: tables.general_category.GeneralCategory,
    /// `Alphabetic`: every `Lu`/`Ll`/`Lt`/`Lm`/`Lo` code point, plus some `Mn`/
    /// `Mc` combining marks, every `Nl` letter-number, and even some `So`
    /// symbols -- verified against every `General_Category` that actually
    /// carries `Alphabetic` in the pinned data, not assumed from the property's
    /// name.
    isAlphabetic: bool,
    /// `Lowercase`, per `DerivedCoreProperties`. Not the same test as
    /// `general().category == .ll`: also true for some `Lm`/`Lo`/`Mn`/`Nl`/`So`
    /// code points, verified against the pinned data.
    isLowercase: bool,
    /// `Uppercase`, per `DerivedCoreProperties`. Not the same test as
    /// `general().category == .lu`: also true for some `Nl`/`So` code points
    /// (not `Lt`, despite title case reading as "uppercase-ish"), verified
    /// against the pinned data.
    isUppercase: bool,
    /// `Cased`: true for anything case conversion can produce or consume,
    /// broader than `general().isUppercase or general().isLowercase` (also true for `Lt`
    /// and code points whose case is otherwise significant).
    isCased: bool,
    /// `Case_Ignorable`: code points a case-insensitive comparison should skip
    /// over rather than compare directly, such as combining marks and some
    /// punctuation. This remains a raw property; `fullCaseFold` performs the
    /// actual default fold and does not treat this predicate as a mapping.
    isCaseIgnorable: bool,
    /// `Math`: mathematical symbols and operators. Broader than
    /// `general().category == .sm`; also true for some `Cf`/`Ll`/`Lo`/`Lu`/
    /// `Mn`/`Nd`/`Pc`/`Pd`/`Pe`/`Po`/`Ps`/`Sk`/`So` code points, verified
    /// against the pinned data.
    isMath: bool,
    /// `ID_Start`: whether a code point may begin a programming-language
    /// identifier under Unicode's recommended default lexical rules. Zunic
    /// implements no lexer; this is the raw property for a caller building one.
    isIdStart: bool,
    /// `ID_Continue`: whether a code point may continue (not necessarily start)
    /// an identifier under the same default rules as `isIdStart`.
    isIdContinue: bool,
    /// `XID_Start`: `ID_Start` closed under Unicode normalization, so an
    /// identifier built from `XID_Start`/`XID_Continue` code points stays valid
    /// after NFKC. Prefer this over `isIdStart` unless a specific lexer grammar
    /// calls for the unclosed property.
    isXidStart: bool,
    /// `XID_Continue`, the `XID_Start` counterpart to `isIdContinue`.
    isXidContinue: bool,
    /// `Default_Ignorable_Code_Point`: code points recommended to be ignored in
    /// rendering absent higher-level protocol support for them -- some format
    /// characters, variation selectors, and deprecated formatting characters.
    /// Zunic's own text view does not consult this property.
    isDefaultIgnorable: bool,
    /// `Grapheme_Base`: roughly, code points that can start a grapheme cluster.
    /// Distinct from `CodepointView.grapheme().gcb`, which is `Grapheme_Cluster_
    /// Break`, a different (UAX #29) property Unicode maintains separately;
    /// `Text.graphemes()` is built on the latter, not this one.
    isGraphemeBase: bool,
    /// `Grapheme_Extend`, the `DerivedCoreProperties` property, not the
    /// `Grapheme_Cluster_Break=Extend` class `CodepointView.grapheme().gcb` reads.
    /// The two agree almost everywhere but not quite: five code points in
    /// Unicode 17.0.0 differ between them. `Text.graphemes()` is built on
    /// `Grapheme_Cluster_Break`, not this property.
    isGraphemeExtend: bool,
    _padding: u14 = 0,
};

/// Terminal-facing facts from one packed table record. For values above
/// 0x10FFFF: neutral EAW, false emoji flags, standalone 1, zeroInGrapheme true.
pub const TerminalProperties = packed struct(u10) {
    eastAsianWidth: tables.terminal_properties.EastAsianWidth,
    /// Whether a scalar has the Unicode `Emoji_Presentation` property.
    isEmojiPresentation: bool,
    /// Whether a scalar is a valid base for VS15/VS16 in the standardized emoji
    /// variation-sequence data.
    isEmojiVariationBase: bool,
    /// Whether a scalar has the Unicode `Emoji_Modifier` property.
    isEmojiModifier: bool,
    /// Whether a scalar has the Unicode `Emoji_Modifier_Base` property.
    isEmojiModifierBase: bool,
    /// Pinned uucode terminal convention; may be 3 (U+2E3B). Differs from width().
    standalone: u2,
    /// Continuation width fact, independent of standalone width.
    zeroInGrapheme: bool,
};

/// Raw extended grapheme clustering facts, fetched together.
pub const GraphemeProperties = packed struct(u7) {
    gcb: tables.properties.GraphemeClass,
    incb: tables.properties.IndicConjunctBreak,
    extendedPictographic: bool,
};
