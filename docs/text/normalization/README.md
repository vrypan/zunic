# Normalization

[Text view](../README.md) · [Documentation index](../../README.md) · [Implementation](implementation.md)

Use `zunic.text(bytes).normalize(form)` to produce a normalized representation
of UTF-8 text. Call `.writeTo(buffer)` for UTF-8 output, or `.next()` to read
normalized `u21` values. There is no `.iterator()` step.

The iterator borrows the input without validating, copying, or allocating on
construction. Keep those bytes alive and unchanged while using it. Processing
happens as you request output, and errors are returned when encountered.

To compare equivalent strings without writing normalized output, use
`eql(other, how)`. To check the existing representation, use
`isNormalized(form)` or `isNormalizedQuick(form)`.

## Choose a form

| Form | Operation | Example |
| --- | --- | --- |
| `.nfd` | Canonical decomposition and combining-mark ordering | `é` → `e` + U+0301 |
| `.nfc` | Canonical decomposition followed by composition | `e` + U+0301 → `é` |
| `.nfkd` | Also apply compatibility decompositions | `ﬁ` → `fi`; `é` → `e` + U+0301 |
| `.nfkc` | Compatibility decomposition followed by composition | `ﬁ` → `fi`; `e` + U+0301 → `é` |

Compatibility forms can remove distinctions such as ligatures, fullwidth
forms, and circled digits. Choose them when those distinctions should be
ignored. Normalization does not fold case; see
[codepoint case folding](../../codepoint/README.md#case-folding).

## API

```zig
pub const Form = enum { nfc, nfd, nfkc, nfkd };
pub const Equivalence = enum { canonical, compatibility };
pub const NormalizationError = error{ InvalidUtf8, SequenceTooLong };
pub const NormalizationWriteError = NormalizationError || error{NoSpace};

pub const QuickCheck = enum { yes, no, maybe };

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

## Iterate or write UTF-8

`normalize()` borrows the input and scans nothing on construction. `next()`
returns the next normalized Unicode scalar as `u21`, `null` at the end, or an
error. Results are newly computed values, not spans into the original bytes.
Unlike [codepoint iteration](../codepoints/README.md), `next()` returns
`u21` values directly and reports errors through `try`, not an `err` field.
Empty input immediately returns `null`.

`writeTo(buffer)` encodes the remaining output into caller-owned storage and
returns the written prefix as `[]u8`, borrowing that output buffer. It
allocates nothing and writes no NUL terminator. Use output storage separate
from the input; this is not an in-place normalization API.

`writeTo` takes its iterator **by value**. A stored iterator is unchanged by
the call, and writing starts from that iterator's current position. Calling
it on a new iterator writes the whole normalized text.

**Normalized output may require more bytes than the original input.** For
example, `é` occupies two UTF-8 bytes, but its NFD form, `e` followed by
U+0301, occupies three. A buffer sized to the input length may be too small.

Use `view.normalizedLenBound(form)` to get a safe upper bound on the output
byte length for the chosen form. Supply a buffer of at least that capacity
to `writeTo()`. The returned slice contains only the bytes actually written;
the buffer may be larger than the result.

```zig
const bytes = "cafe\u{0301}";
const capacity = comptime try zunic.text(bytes).normalizedLenBound(.nfc);
var buffer: [capacity]u8 = undefined;
const result = try zunic.text(bytes).normalize(.nfc).writeTo(&buffer);
std.debug.print("{s}\n", .{result});
std.debug.print("Used {d} of {d} bytes\n", .{ result.len, buffer.len });
// Output:
// café
// Used 5 of 18 bytes
```

For codepoint output, iterate directly:

```zig
var it = zunic.text("é").normalize(.nfd);
while (try it.next()) |value| {
    std.debug.print("U+{X}\n", .{value});
}
// Output:
// U+65
// U+301
```

The bound is calculated from the input length without scanning, validating,
or normalizing its bytes. It returns `Overflow` if the capacity cannot fit in
`usize`. Providing this much space prevents `NoSpace`; malformed input and
over-limit combining runs can still produce errors.

Use the same form for the bound and for normalization. For runtime input,
call `try zunic.text(input).normalizedLenBound(form)` and supply a buffer of
that capacity. The example uses `comptime` because its input length is known,
so the capacity can be used as a local array length.

## Query normalization and equality

`isNormalized(form)` tests whether the input is already in that form.
`eql(other, how)` compares forms without creating output strings, in lockstep
over both inputs. `.canonical` handles composed and decomposed spellings but
not compatibility or case differences; `.compatibility` also treats a
ligature, fullwidth form, or similar as equivalent to its expansion, at the
cost of also erasing that distinction. Neither ignores case.

```zig
std.debug.print("canonical: {}\n", .{
    try zunic.text("café").eql("cafe\u{0301}", .canonical),
});
std.debug.print("ligature, canonical: {}\n", .{
    try zunic.text("ﬁ").eql("fi", .canonical),
});
std.debug.print("ligature, compatibility: {}\n", .{
    try zunic.text("ﬁ").eql("fi", .compatibility),
});
std.debug.print("already NFC: {}\n", .{try zunic.text("café").isNormalized(.nfc)});
// Output:
// canonical: true
// ligature, canonical: false
// ligature, compatibility: true
// already NFC: true
```

Both queries can stop at a decisive `false` and leave later bytes unexamined.
They are not whole-input validators. Errors encountered before a decision are
returned. A successful `true` means both complete inputs were accepted for
equality, or the complete input for `isNormalized`.

`isNormalizedQuick(form)` is the UAX #15 quick check itself, and returns
`yes`, `no` or `maybe`:

```zig
const result = try zunic.text("q\u{0301}").isNormalizedQuick(.nfc);
std.debug.print("{s}\n", .{@tagName(result)});
// Output:
// maybe
```

`maybe` means more context is needed. Use `isNormalized()` for a definite
boolean answer. NFD and NFKD return only `yes` or `no`.

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

By default, a fully decomposed combining run may contain at most 30
consecutive non-starters (characters with nonzero canonical combining class).
The limit applies after decomposition, including compatibility decomposition
for NFKC/NFKD; one input character can expand into several counted values.

The default of 30 follows the threshold in Unicode's
[Stream-Safe Text Format](https://www.unicode.org/reports/tr15/#Stream_Safe_Text_Format).
Unicode chose it to leave a generous margin for linguistic and technical
usage while permitting small normalization buffers. Zunic accommodates that
default in 128 bytes: 32 four-byte entries, with two reserved for the starter
and spare space.

Zunic adopts the threshold, not the Stream-Safe process. Stream-Safe counts
non-starters after NFKD and inserts CGJ separators when processing longer
runs. Zunic counts after the decomposition appropriate to the requested form
and returns `SequenceTooLong` when its configured limit is exceeded. Longer
runs are still valid Unicode; this is a resource limit, not a validity rule.

Configure it with `-Dnormalization-buffer-bytes=N`, a positive multiple of 32.
The accepted limit is `N / 4 - 2`: 128 bytes permits 30 non-starters, and
256 bytes permits 62. **Increasing this setting increases the size of every
normalization iterator**, because each iterator contains its own working
buffer. The total iterator size is larger than this setting: it also includes
state and scratch storage. This setting does not size the output buffer
passed to `writeTo()`. See [build options](../../internals/README.md#build-options)
and [buffer implementation](implementation.md#buffer-one-combining-run).

Over-limit input is rejected. Zunic does not insert separators, truncate marks,
or silently allocate a larger buffer.

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
