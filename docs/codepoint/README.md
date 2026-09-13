# Codepoints

[Documentation index](../README.md) · [Text view](../text/README.md) · [Implementation](implementation.md)

Use `zunic.cp(value)` if you have a codepoint stored as a `u21` and want to
query its properties. This gives you access to its Unicode category and
script, numeric value, normalization facts, emoji properties, isolated
display width, or case-folded values.

```zig
const value: u21 = 0x1f600; // U+1F600, 😀
const point = zunic.cp(value);
std.debug.print("Emoji presentation: {}\n", .{point.terminal().isEmojiPresentation});
std.debug.print("Isolated width: {d}\n", .{point.width()});
// Emoji presentation: true
// Isolated width: 2
```

The property groups return several related answers together. For example,
`const general = point.general();` lets you read `general.category` and
`general.isAlphabetic` from the same result.

If you have UTF-8 bytes, use `zunic.text(bytes).codepoints().iterator()` to
read one codepoint at a time. Each result is already a `CodepointView` with
the same methods as `cp(value)`. See the
[codepoint iterator documentation](../text/codepoints/README.md).

`cp()` allocates nothing, decodes no bytes, and performs no lookup during
construction. Its methods use Unicode 17.0.0 data, exposed as
`zunic.unicode_version`.

## API

The constructor accepts a value and returns a `CodepointView`:

```zig
pub fn cp(value: u21) CodepointView;
// CodepointView exposes:
value: u21,
```

## Codepoints, bytes, and graphemes

A codepoint is a number in Unicode's range `0..0x10FFFF`. Zunic uses `u21`
because 21 bits are enough to represent every number in that range; 20 are
not. This describes a numeric value, not how text is stored or read.

UTF-8 encodes each Unicode scalar value in one to four bytes. A decoder reads
the first byte, determines the sequence length, validates the sequence, and
combines its payload bits into a codepoint value. It does not read text in
21-bit chunks.

| Text | UTF-8 bytes, hexadecimal | Decoded values |
| --- | --- | --- |
| `A` | `41` | `0x0041` |
| `😀` | `F0 9F 98 80` | `0x1F600` |
| `e` followed by a combining acute accent | `65 CC 81` | `0x0065`, `0x0301` |

The last example contains two codepoints but one extended grapheme cluster.
Use [grapheme iteration](../text/graphemes/README.md) when you need clusters
rather than individual values.

## Construction and valid values

`cp()` accepts every `u21` without validation. A `u21` can also represent
numbers above Unicode's maximum, up to `0x1FFFFF`.

A Unicode *scalar value* excludes surrogate codepoints `0xD800..0xDFFF`.
Surrogates are inside the codepoint range but cannot occur in valid UTF-8.
For an arbitrary `u21`, the scalar-value check is:

```zig
const value: u21 = 0x1f600;
const is_scalar = value <= zunic.max_codepoint and
    !(value >= 0xd800 and value <= 0xdfff);
std.debug.print("Unicode scalar: {}\n", .{is_scalar});
// Unicode scalar: true
```

U+FFFD, the replacement character, is a valid scalar value. Its presence does
not by itself indicate an error. `CodepointView` has no `isValid()` method.

## Property groups

Each group returns a value containing related facts. Retain that result when
reading several fields. The three groups use separate lookups; calling one
does not populate or cache the others.

| Method | Return type | Contents |
| --- | --- | --- |
| `general()` | `zunic.GeneralProperties` | General category and derived boolean properties |
| `terminal()` | `zunic.TerminalProperties` | East Asian width, emoji flags, and terminal width facts |
| `grapheme()` | `zunic.GraphemeProperties` | Classification used by grapheme segmentation |
| `bidi()` | `zunic.BidiProperties` | Bidi class, mirrored status, and paired-bracket type |

Script properties are separate methods: `script()` returns a `zunic.Script`,
and `scriptExtensions()` returns the codepoint's exact set of possible scripts.

### General properties

`general().category` is a `zunic.GeneralCategory`, with values such as `.lu`
(uppercase letter), `.ll` (lowercase letter), `.nd` (decimal digit), and `.cn`
(unassigned). Category names are lowercase; `No` is spelled `.no_` in Zig.

The boolean fields are:

| Fields | Unicode properties |
| --- | --- |
| `isAlphabetic`, `isLowercase`, `isUppercase` | `Alphabetic`, `Lowercase`, `Uppercase` |
| `isCased`, `isCaseIgnorable` | `Cased`, `Case_Ignorable` |
| `isChangesWhenLowercased`, `isChangesWhenUppercased`, `isChangesWhenTitlecased` | `Changes_When_Lowercased`, `Changes_When_Uppercased`, `Changes_When_Titlecased` |
| `isChangesWhenCasefolded`, `isChangesWhenCasemapped` | `Changes_When_Casefolded`, `Changes_When_Casemapped` |
| `isMath` | `Math` |
| `isIdStart`, `isIdContinue` | `ID_Start`, `ID_Continue` |
| `isXidStart`, `isXidContinue` | `XID_Start`, `XID_Continue` |
| `isDefaultIgnorable` | `Default_Ignorable_Code_Point` |
| `isGraphemeBase`, `isGraphemeExtend` | `Grapheme_Base`, `Grapheme_Extend` |

These are independent Unicode properties. For example, `isUppercase` is not
equivalent to `category == .lu`, and `isGraphemeExtend` is not equivalent to
`grapheme().gcb == .extend`. Identifier properties supply character facts;
they do not validate an entire identifier or implement a language's rules.

The `isChangesWhen...` flags predict whether the corresponding default Unicode
lowercase, uppercase, titlecase, case-folding, or case-mapping operation would
change the code point. They report the DerivedCoreProperties facts; they do not
perform a mapping, encode its result, or choose locale- or context-sensitive
behavior.

### Terminal properties

| Field | Type | Meaning |
| --- | --- | --- |
| `eastAsianWidth` | `zunic.EastAsianWidth` | `.neutral`, `.narrow`, `.wide`, `.fullwidth`, `.halfwidth`, or `.ambiguous` |
| `isEmojiPresentation` | `bool` | Unicode `Emoji_Presentation` |
| `isEmojiVariationBase` | `bool` | Base in the standardized emoji variation sequences |
| `isEmojiModifier` | `bool` | Unicode `Emoji_Modifier` |
| `isEmojiModifierBase` | `bool` | Unicode `Emoji_Modifier_Base` |
| `standalone` | `u2` | Standalone width using the pinned uucode convention; can be 3 |
| `zeroInGrapheme` | `bool` | Separate zero-width continuation fact for a codepoint within a grapheme |
| `isEmoji` | `bool` | Unicode `Emoji` |
| `isEmojiComponent` | `bool` | Unicode `Emoji_Component` |

`standalone` differs from `width()`. For example, U+2E3B has `standalone == 3`,
whereas `width()` always returns 0, 1, or 2. These are scalar facts; calculating
the width of a whole cluster requires context.

### Grapheme properties

| Field | Type | Meaning |
| --- | --- | --- |
| `gcb` | `zunic.GraphemeClass` | Grapheme cluster break classification |
| `incb` | `zunic.IndicConjunctBreak` | Indic conjunct break classification |
| `extendedPictographic` | `bool` | Unicode `Extended_Pictographic` |

These facts alone do not decide a boundary. Use
[text grapheme iteration](../text/graphemes/README.md) for UTF-8 text, or
`zunic.graphemeBreak(previous, current, &state)` with `zunic.GraphemeState`
for [incremental codepoint input](grapheme-break.md). Both apply the contextual
segmentation rules.

### Script properties

`script()` returns the primary Unicode `Script` value. `scriptExtensions()`
returns the explicit `Script_Extensions` set when Unicode defines one;
otherwise it returns a one-element slice containing the primary script. The
slice borrows immutable table storage and remains valid for the program
lifetime. Its members are sorted by `Script` enum order for deterministic
iteration; that order has no linguistic priority.

`zunic.Script` uses lowercase canonical long names such as `.latin` and
`.old_italic`. The tags are public API; their numeric ordinals are not a
stable serialization format.

```zig
const prolonged = zunic.cp(0x30fc); // KATAKANA-HIRAGANA PROLONGED SOUND MARK
std.debug.print("primary: {s}\n", .{@tagName(prolonged.script())});
for (prolonged.scriptExtensions()) |script| {
    std.debug.print("extension: {s}\n", .{@tagName(script)});
}
// primary: common
// extension: hiragana
// extension: katakana
```

An explicit extension set replaces the default; the example therefore does
not include `.common`. These methods provide per-codepoint facts. They do not
detect a language, resolve `.common` or `.inherited` from surrounding text,
segment script runs, or enforce a mixed-script policy.

### Bidirectional properties

`bidi()` returns three Unicode facts in one byte: `class`, `isMirrored`, and
`pairedBracketType`. The class uses canonical long names such as
`.left_to_right`, `.arabic_letter`, and `.pop_directional_isolate`. Bracket
type is `.none`, `.open`, or `.close`.

```zig
const parenthesis = zunic.cp('(');
const bidi = parenthesis.bidi();
std.debug.print("{s}, mirrored={}, bracket={s}\n", .{
    @tagName(bidi.class), bidi.isMirrored, @tagName(bidi.pairedBracketType),
});
// other_neutral, mirrored=true, bracket=open
```

`bidiMirroringGlyph()` and `bidiPairedBracket()` return the encoded mapping or
`null` when Unicode defines none. Mirrored status does not imply an encoded
mirror: U+2211 SUMMATION is mirrored but has no `Bidi_Mirroring_Glyph` mapping.
These methods expose per-codepoint input facts for a bidirectional layout
engine. They do not determine paragraph direction, embedding levels, display
order, bracket resolution, or glyph shaping.

## Width, whitespace, and case folding

| Method | Return type | Meaning |
| --- | --- | --- |
| `width()` | `u2` | Zunic's isolated codepoint width, 0–2 columns |
| `isEastAsianWide()` | `bool` | Whether East Asian width is Wide, Fullwidth, or Halfwidth |
| `isWhitespace()` | `bool` | Unicode `White_Space`, the same 25-codepoint set used by text trimming |
| `fullCaseFold()` | `zunic.CaseFold` | Full default Unicode case-fold mapping |

Do not sum `width()` values to calculate text width: combining sequences,
flags, and emoji sequences need cluster measurement. Use
[text width](../text/width/README.md) or
[measured grapheme iteration](../text/graphemes/README.md#measured-results).
Also, `isEastAsianWide()` includes Halfwidth,
so `true` does not imply a width of two.

`isWhitespace()` includes no-break spaces U+00A0 and U+202F. It excludes
U+200B, U+FEFF, and U+2060. The property does not decide whether a line may
break at that position.

## Numeric values

Use `numeric()` when you need the exact numeric value assigned by Unicode:

```zig
const examples = [_]struct { character: []const u8, codepoint: u21 }{
    .{ .character = "5", .codepoint = '5' },
    .{ .character = "²", .codepoint = 0x00b2 },
    .{ .character = "⅓", .codepoint = 0x2153 },
};
for (examples) |example| {
    const value = zunic.cp(example.codepoint).numeric().?;
    std.debug.print("{s} = {d}/{d} ({s})\n", .{
        example.character,
        value.numerator,
        value.denominator,
        @tagName(value.kind),
    });
}
// 5 = 5/1 (decimal)
// ² = 2/1 (digit)
// ⅓ = 1/3 (numeric)
```

The result's `kind` is `.decimal`, `.digit`, or `.numeric`. Decimal values are
the positional digits used by decimal numbering systems. Digit includes
characters such as superscripts. Numeric covers other values, including
fractions, negative values, and large integers. `numerator` is an `i64` and
`denominator` is a positive `u16`; the fraction is reduced. A codepoint with no
Unicode numeric value returns `null`.

## Normalization facts

`canonicalCombiningClass()` returns the codepoint's Unicode canonical
combining class as a `u8`; zero is the default. `decomposition()` returns its
immediate Unicode decomposition, if any:

```zig
const value = zunic.cp(0x00e9); // é
std.debug.print("Class: {d}\n", .{value.canonicalCombiningClass()});
const decomposition = value.decomposition().?;
for (decomposition.mapping) |part| {
    std.debug.print("U+{X}\n", .{part});
}
// Class: 0
// U+65
// U+301
```

`decomposition.type` distinguishes canonical mappings from the compatibility
types `.font`, `.no_break`, `.initial`, `.medial`, `.final`, `.isolated`,
`.circle`, `.super`, `.sub`, `.vertical`, `.wide`, `.narrow`, `.small`,
`.square`, `.fraction`, and `.compat`. The mapping slice borrows immutable
Unicode table data and remains valid for the program lifetime.

This is the immediate mapping recorded in `UnicodeData.txt`, not recursive
normalization. Hangul syllable decomposition is algorithmic and therefore does
not appear here. Use [text normalization](../text/normalization/README.md) to
produce NFC, NFD, NFKC, or NFKD output. `fullCompositionExclusion` reports
whether a canonical mapping has Unicode's `Full_Composition_Exclusion` fact.

### Simple case mappings

Use `simpleUppercase()`, `simpleLowercase()`, and `simpleTitlecase()` when one
codepoint must map to exactly one codepoint:

```zig
std.debug.print("U+{X}\n", .{zunic.cp(0x01c6).simpleUppercase()}); // ǆ → Ǆ
std.debug.print("U+{X}\n", .{zunic.cp(0x01c6).simpleTitlecase()}); // ǆ → ǅ
std.debug.print("U+{X}\n", .{zunic.cp(0x01c4).simpleLowercase()}); // Ǆ → ǆ
// U+1C4
// U+1C5
// U+1C6
```

An unmapped value returns itself. These methods apply the simple mappings in
`UnicodeData.txt`; they do not expand one codepoint into several or apply
contextual and locale-sensitive rules. For example, `simpleUppercase()` leaves
`ß` unchanged even though full uppercase conversion can produce `SS`.

### Case folding

`fullCaseFold()` returns the full default Unicode case-fold mapping. One
codepoint may expand to several values:

```zig
const folded = zunic.cp(0x00df).fullCaseFold(); // ß → ss
for (folded.slice()) |value| {
    std.debug.print("U+{X}\n", .{value});
}
// U+73
// U+73
```

`CaseFold` owns a fixed `codepoints: [3]u21` buffer and a `len: u2`. Its
`slice(self: *const CaseFold) []const u21` borrows the populated prefix, so
keep the result alive while using the slice. Unmapped values fold to
themselves. Folding does not normalize text or perform locale-sensitive casing.

## Values above Unicode's maximum

Operations have defined fallbacks for values above `zunic.max_codepoint`:

| Operation | Result |
| --- | --- |
| `general()` | `.cn`, all boolean fields false |
| `terminal()` | Neutral East Asian width, emoji flags false, `standalone = 1`, `zeroInGrapheme = true` |
| `grapheme()` | `.other`, `.none`, `extendedPictographic = false` |
| `width()` | `1` |
| `isEastAsianWide()`, `isWhitespace()` | `false` |
| `fullCaseFold()` | The original value |
| Simple case mappings | The original value |
| `numeric()`, `decomposition()` | `null` |
| `canonicalCombiningClass()` | `0` |
| `script()`, `scriptExtensions()` | `.unknown`, singleton `.unknown` |
| `bidi()` | `.left_to_right`, mirrored false, bracket type `.none` |
| `bidiMirroringGlyph()`, `bidiPairedBracket()` | `null` |

These fallbacks do not make the input a valid scalar. Surrogates are a
different case: they are within Unicode's range and use their table entries,
including general category `.cs`. Use the scalar-value check above when
accepting arbitrary values for UTF-8 encoding.
