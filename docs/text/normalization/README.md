# Normalization

[Text view](../README.md) · [Documentation index](../../README.md) · [Implementation](implementation.md)

Normalization provides all four Unicode 17 normalization forms. NFD decomposes
characters canonically and orders combining marks; NFC also combines
characters where canonical composition is possible. NFKD and NFKC do the same,
but decompose compatibility mappings too -- ligatures, fullwidth and
half-width forms, circled and superscript digits, and similar -- which NFC and
NFD never touch. Case folding is a separate scalar operation exposed as
`cp(value).fullCaseFold()`; normalization does not apply it implicitly.

Compatibility equivalence, `eql(..., .compatibility)`, is a separate, coarser
relation than canonical equivalence: `"\u{FB01}"` (a ligature) and `"fi"` are
compatibility-equivalent but not canonically equivalent. Choosing it is an
explicit decision by the caller, not a default -- see
[Query normalization and equality](#query-normalization-and-equality).

## Unicode standards

The methods use Unicode 17.0.0 normalization as described in
[UAX #15: Unicode Normalization Forms](https://www.unicode.org/reports/tr15/):

- `normalize()`, `next()`, and `writeTo()` produce NFC, NFD, NFKC, or NFKD.
- `isNormalized()` checks the selected form, including its quick-check rules.
- `eql(..., .canonical)` compares canonical equivalence through NFD;
  `eql(..., .compatibility)` compares compatibility equivalence through NFKD.
- `normalizedLenBound()` is a Zunic capacity helper derived from the pinned data, not a separate UAX operation.

- `isNormalizedQuick()` is the UAX #15 quick check itself, three-valued for
  the two composing forms and two-valued for the two decomposing ones.

The configurable run limit is a Zunic restriction. It does not implement
UAX #15's Stream-Safe Text Format, which uses a different counting rule and
inserts separators. Zunic returns `SequenceTooLong` instead.

## Signatures

```zig
pub const Form = enum { nfc, nfd, nfkc, nfkd };
pub const Equivalence = enum { canonical, compatibility };
pub const NormalizationError = error{ InvalidUtf8, SequenceTooLong };
pub const NormalizationWriteError = NormalizationError || error{NoSpace};

pub const QuickCheck = enum { yes, no, maybe };
pub const unicode_version: std.SemanticVersion; // the pinned data version

pub fn NormalizationIterator(comptime form: Form) type;

// NormalizationIterator(form), with Self standing for that concrete type
pub fn next(self: *Self) NormalizationError!?u21;
pub fn writeTo(self: Self, buffer: []u8) NormalizationWriteError![]u8;

// Text methods
pub fn normalize(self: Text, comptime form: Form) NormalizationIterator(form);
pub fn normalizedLenBound(self: Text, comptime form: Form) error{Overflow}!usize;
pub fn eql(self: Text, other: []const u8, comptime how: Equivalence) NormalizationError!bool;
pub fn isNormalized(self: Text, comptime form: Form) NormalizationError!bool;
pub fn isNormalizedQuick(self: Text, comptime form: Form) error{InvalidUtf8}!QuickCheck;
```

These signatures use the exported names from `zunic`. `form` and `how` must
be known at compile time. All normalization operations start from a text view:
`zunic.text(bytes).normalize(.nfc)`. The iterator produces new scalars rather
than spans into the input.

`unicode_version` is the version of the pinned Unicode data. It is not Zunic's
package version and is unrelated to the Zig version in use. Each table
generator's verifier asserts it against the vendored UCD filenames.

## Iterate or write UTF-8

`normalize()` borrows the input and scans nothing on construction. `next()`
returns the next normalized Unicode scalar as `u21`, `null` at the end, or an
error. Scalars are newly computed values, not spans into the original bytes.
Empty input immediately returns `null`.

`writeTo(buffer)` encodes the remaining output into caller-owned storage and
returns the written prefix as `[]u8`. It allocates nothing and writes no NUL
terminator. Use output storage separate from the input; this is not an in-place
normalization API.

`writeTo` takes its iterator **by value**. A stored iterator is unchanged by
the call, and writing starts from that iterator's current position. Calling
it on a new iterator writes the whole normalized text.

```zig
const bytes = "cafe\u{0301}";
const capacity = comptime try zunic.text(bytes).normalizedLenBound(.nfc);
var buffer: [capacity]u8 = undefined;
const result = try zunic.text(bytes).normalize(.nfc).writeTo(&buffer);
try std.testing.expectEqualStrings("café", result);
try std.testing.expectEqual(@as(usize, 4), zunic.text(result).width());

var scalars = zunic.text("é").normalize(.nfd);
try std.testing.expectEqual(@as(u21, 'e'), (try scalars.next()).?);
try std.testing.expectEqual(@as(u21, 0x301), (try scalars.next()).?);
try std.testing.expect((try scalars.next()) == null);
```

`text.normalizedLenBound(form)` returns a safe output byte-capacity bound for
the requested form, with checked arithmetic; an unrepresentable result is
`Overflow`. It is a capacity bound, not the exact output size, and does not
examine or validate input. Supplying this much space rules out `NoSpace` only.

The bound is `3 * text.bytes.len` for NFC/NFD and `11 * text.bytes.len` for
NFKC/NFKD -- compatibility mappings can expand much further than canonical
ones (U+FDFA, an Arabic ligature, is three bytes in and thirty-three out).
Sizing a buffer with the wrong form's bound risks `NoSpace` on real input, not
just a pathological one.

```zig
const capacity = comptime try zunic.text("é").normalizedLenBound(.nfd);
try std.testing.expectEqual(@as(usize, 6), capacity);
var it = zunic.text("é").normalize(.nfd);
_ = try it.next(); // Consume 'e'.
var buffer: [capacity]u8 = undefined;
try std.testing.expectEqualStrings("\u{0301}", try it.writeTo(&buffer));
// writeTo copied the iterator; its next scalar is still the accent.
try std.testing.expectEqual(@as(u21, 0x301), (try it.next()).?);
```

These examples use `comptime` because the input lengths are known at compile
time, allowing a local array of the calculated size. For runtime input, call
`try zunic.text(input).normalizedLenBound(form)` and supply a buffer with that capacity.

## Query normalization and equality

`isNormalized(form)` tests whether the input is already in that form.
`eql(other, how)` compares forms without creating output strings, in lockstep
over both inputs. `.canonical` handles composed and decomposed spellings but
not compatibility or case differences; `.compatibility` also treats a
ligature, fullwidth form, or similar as equivalent to its expansion, at the
cost of also erasing that distinction. Neither ignores case.

```zig
try std.testing.expect(try zunic.text("café").eql("cafe\u{0301}", .canonical));
try std.testing.expect(try zunic.text("café").isNormalized(.nfc));
try std.testing.expect(!try zunic.text("café").isNormalized(.nfd));
try std.testing.expect(!try zunic.text("ﬁ").eql("fi", .canonical));

// The same pair, compared the other way: equivalent by expansion, not by
// canonical spelling. Neither call reaches for the other's answer -- the
// caller decides up front which distinction matters. NFC never applies a
// compatibility mapping, so the ligature is already NFC-normalized; NFKC is
// what expands it.
try std.testing.expect(try zunic.text("ﬁ").eql("fi", .compatibility));
try std.testing.expect(try zunic.text("ﬁ").isNormalized(.nfc));
try std.testing.expect(!try zunic.text("ﬁ").isNormalized(.nfkc));
```

Both queries can stop at a decisive `false` and leave later bytes unexamined.
They are not whole-input validators. Errors encountered before a decision are
returned. A successful `true` means both complete inputs were accepted for
equality, or the complete input for `isNormalized`.

`isNormalizedQuick(form)` is the UAX #15 quick check itself, and returns
`yes`, `no` or `maybe`:

```zig
try std.testing.expectEqual(zunic.QuickCheck.yes, try zunic.text("café").isNormalizedQuick(.nfc));
try std.testing.expectEqual(zunic.QuickCheck.no, try zunic.text("café").isNormalizedQuick(.nfd));
try std.testing.expectEqual(zunic.QuickCheck.maybe, try zunic.text("q\u{0301}").isNormalizedQuick(.nfc));
try std.testing.expectEqual(zunic.QuickCheck.no, try zunic.text("ﬁ").isNormalizedQuick(.nfkc));
```

`maybe` is an answer, not a failure: it means the question depends on context
the check does not gather. `isNormalized()` settles it and returns a boolean,
at a cost. NFD and NFKD are never `maybe`: a decomposition (canonical for
NFD, canonical or compatibility for NFKD) is a definite `no`, with nothing
left to depend on context. `NFKC_QC` is a separate property from `NFC_QC`,
not derived from it: a code point can quick-check `yes` under NFC while
quick-checking `no` under NFKC, when its canonical decomposition target is
itself compatibility-decomposable.

Three differences from `isNormalized()` are worth knowing:

- It always reads the whole slice, so malformed UTF-8 after a decisive `no` is
  still reported. `isNormalized()` may stop earlier and miss it.
- It does **not** enforce Zunic's configured run limit. A `yes` therefore does
  not promise that `normalize()` will accept the input: a run longer than the
  limit can be perfectly normalized and still `SequenceTooLong`.
- Its only error is `InvalidUtf8`.

## Errors and partial results

| Error | Meaning |
| --- | --- |
| `InvalidUtf8` | A malformed UTF-8 sequence was reached. No replacement character is substituted. |
| `SequenceTooLong` | A fully decomposed combining run exceeds the configured non-starter limit. |
| `NoSpace` | The output buffer cannot hold the next complete encoded scalar. |
| `Overflow` | The length-bound calculation cannot fit in `usize`. Only `normalizedLenBound` returns this. |

Once `next()` returns an error, later calls return the same error. Previously
returned scalars remain valid, but a run may fail before any of it is emitted.
For example, `"ab\xff"` yields `a`, then `InvalidUtf8`; it need not yield `b`.

On a failed `writeTo`, previously written bytes remain in the buffer. `NoSpace`
never writes part of a UTF-8 scalar. To retry, call `writeTo` again with more
space from the same saved iterator state, or create a new iterator for the
whole input. More space does not fix invalid UTF-8 or an over-limit run.

## Combining-run limit

The default working buffer is 128 bytes, allowing 30 consecutive non-starters
after full decomposition -- canonical for NFC/NFD, canonical and compatibility
for NFKC/NFKD. A non-starter is a character with a nonzero canonical combining
class. The count applies to decomposed characters, not input bytes or the
number of marks visible in the original spelling, and is the same limit and
the same rule for all four forms: a compatibility mapping's own expansion is
counted exactly like a canonical one's.

The build option `-Dnormalization-buffer-bytes=N` accepts positive multiples of
32. Each entry uses four bytes; the accepted non-starter limit is `N / 4 - 2`.
For example, 256 bytes permits 62. This sizes the iterator's inline working
buffer, not its complete object: the iterator also stores input, state, and
scratch space, and the scratch space is larger for NFKC/NFKD than for NFC/NFD
(see [implementation](implementation.md#a-second-scratch-buffer-for-compatibility-mappings)).
See [build options](../../internals/README.md#build-options).

Over-limit input is rejected. Zunic does not insert separators, truncate marks,
or silently allocate a larger buffer.
