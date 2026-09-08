# Word-boundary implementation decisions

[API](README.md) · [Source](../../src/word.zig)

## Remember both immediate and significant characters

Some rules depend on adjacent characters, while others ignore intervening
marks and formatting characters. The iterator keeps the immediately preceding
word class as well as the last two non-ignored classes. This avoids losing
the distinction between an adjacent ZWJ and one separated from an emoji by a
formatting character. Regional-indicator pairing needs only an odd/even flag.

## Store repeated decisions once

Early rules are evaluated directly. The later rules are evaluated at compile
time into a decision table. Many combinations of remembered classes produce
the same row, so those rows are stored once. State updates remain simple
assignments; they do not need a second table.

Both the table and the direct reference implementation use the same rule
function. Tests compare their results. The compiled table has an 8 KiB build
limit to catch unexpected growth when rules or properties change.

## Look ahead only when a rule asks

Punctuation rules sometimes need the next non-ignored character, as in a
letter–apostrophe–letter sequence. The iterator only scans ahead for those
decisions. It may cross a long run of ignored marks, but each such run belongs
to one candidate punctuation character. A full traversal therefore performs
less than twice as many scalar decodes as there are input scalars.

## Compute the flag while scanning

[word_properties.zig](../../src/word_properties.zig) supplies the word class,
pictographic bit, and word-like bit together. The iterator accumulates the
word-like bit as it consumes each segment. It does not scan the returned slice
again to compute `is_word`.

The word-like bit cannot be inferred from the word class: an ideograph and a
superscript number can have class `Other` and still qualify. Keeping separate
data preserves the documented flag without changing boundary decisions.

[Word tests](../../src/word_test.zig) cover the Unicode fixtures, the flag,
malformed input, reference/table agreement, and lookahead work limits.
