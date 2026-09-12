# Changelog

Notable code changes are listed by package version. Documentation-only,
benchmark-only, planning, release bookkeeping, and intermediate changes that
were superseded before the same release are omitted.

## [0.4.0] - 2026-09-12

### Added

- Added `cp(u21)` codepoint views with grouped general, terminal, and grapheme
  properties, isolated width, whitespace, case, numeric, combining-class, and
  decomposition operations.
- Added strict UTF-8 codepoint iteration through `text(bytes).codepoints()`;
  iteration stops at malformed input and retains a sticky error for callers
  that need it.
- Added full default case folding and simple uppercase, lowercase, and
  titlecase mappings.
- Added incremental extended-grapheme decisions through `GraphemeState` and
  `graphemeBreak`.
- Added NFKC and NFKD normalization and compatibility equality.
- Added `isAscii` queries for byte slices and text views.

### Changed

- Updated all Unicode data and conformance fixtures from Unicode 16.0.0 to
  Unicode 17.0.0.
- Reorganized the public API around the `cp(u21)` and `text([]const u8)` entry
  points.
- Fused terminal properties into one lookup and split grapheme/width facts
  into a compact table so codepoint-only users do not link the larger layout
  table.
- Replaced simple-case and immediate-decomposition lookups with compact
  two-stage tables, and consolidated normalization decisions into fewer
  lookups.
- Inlined the grapheme decoding and public iterator chain and added a dedicated
  fast path for entirely ASCII word-boundary input.

### Fixed

- Corrected normalization quick checks and repeated-ZWJ grapheme boundaries.

### Removed

- Removed the ANSI-aware terminal view, escape parser, and ANSI stripping API.

## [0.3.1] - 2026-09-10

### Added

- Added Unicode `White_Space` queries for codepoints and text spans.
- Added allocation-free `trim`, `trimStart`, and `trimEnd` text views.

## [0.3.0] - 2026-09-10

### Added

- Added the borrowed `text(bytes)` API for grapheme iteration, width,
  terminators, wrapping, word boundaries, validation, and normalization.
- Added default Unicode word-boundary segmentation.
- Added canonical NFC and NFD normalization, normalization quick checks,
  canonical equality, caller-buffer output, and the Stream-Safe combining-run
  limit.
- Added an ANSI-aware terminal view with escape-aware grapheme iteration,
  parsed formatting effects, and allocation-free ANSI stripping.

### Changed

- Replaced the generic line-break implementation with a generated transition
  machine and drove grapheme segmentation from a compile-time transition
  table.
- Split encoding, segmentation, layout, line breaking, normalization, tables,
  and terminal handling into enforced internal modules.
- Reused decoded scalar and grapheme facts across width and wrapping, including
  whole-run handling for fitting ASCII lines and printable ASCII width.

## [0.2.4] - 2026-09-06

### Changed

- Fused grapheme, width, and line-break properties into a shared codepoint
  lookup.

## [0.2.3] - 2026-09-06

### Changed

- Extended the direct ASCII wrapping path to punctuation-heavy text.

## [0.2.2] - 2026-09-06

### Changed

- Added tested ARM64 and x86_64 SIMD paths for ASCII wrapping and skipped
  Unicode decoding and property searches for ASCII scalars.
- Measured printable ASCII width by byte length and reused grapheme measures in
  whole-text width calculations.

## [0.2.1] - 2026-09-05

### Changed

- Fused wrapping into one decoding and classification pass.

## [0.2.0] - 2026-09-05

### Added

- Added allocation-free terminal-column wrapping.
- Added shared decoded scalar facts for grapheme width and line breaking.

### Changed

- Added a direct fast path for simple ASCII paragraphs and bounded automatic
  SIMD selection to supported targets.
- Reused grapheme measurements and line-break classes throughout wrapping.

### Fixed

- Preserved ASCII space runs when wrapping.

## [0.1.0] - 2026-09-05

### Added

- Initial allocation-free UTF-8, grapheme, width, and Unicode 16 UAX #14
  line-breaking primitives.
