//! Native throughput benchmarks over pinned corpora.
//!
//! Each case reports per-sample timings plus a checksum, so a run proves what
//! it measured still produces the same bytes. `src/tools/benchmark-history.py`
//! archives a run and compares two of them; see `private/` for the Rust peer
//! comparisons, which answer a different question.
//!
//! Row names and checksums are a compatibility surface: adding a case is
//! fine, renaming or redefining one silently invalidates every stored
//! archive. Bump `harness_version` when the set changes.
const std = @import("std");
const zunic = @import("zunic");
const corpora = @import("corpora.zig");

// The public traversal and checksum coordinate types changed in 0.3.0, so
// results from earlier harnesses are deliberately not comparable. Version 4
// adds the `measured` operation; version 3 archives do not contain that row.
// Version 5 adds the eight profile-generated document corpora.
// Version 6 adds the `terminators` operation.
// Version 7 adds the `word_bounds` operation and its dedicated corpora.
// Version 8 adds the normalization operations and their dedicated corpora.
// Version 9 adds `nfc_quick` and `nfd_quick` beside the existing
// normalization rows. Old names and checksums are untouched, so a
// version-8 archive still compares row for row against the shared cases.
// Versions 10-12 covered the removed ANSI terminal view.
// Version 13 adds the trim rows and their dedicated corpora. Every earlier row
// name, corpus and checksum is untouched.
// Version 14 adds the is_ascii rows and their dedicated corpora. Every
// earlier row name, corpus and checksum is untouched.
// Version 15 adds nfkc/nfkd/is_nfkc/nfkc_quick/nfkd_quick/eql_compat rows on
// the existing normalization corpora, plus dedicated compat_corpora for
// compatibility-mapping-heavy input. Every earlier row name, corpus and
// checksum is untouched.
// Version 16 removes the ANSI terminal-view rows.
const harness_version = "16";
const sample_count = 7;
const Corpus = struct { name: []const u8, seed: []const u8, length: usize };
const WrapCase = struct { name: []const u8, corpus: Corpus, max_columns: usize, overflow: zunic.Overflow, max_lines: ?usize = null };

const legacy_corpora = [_]Corpus{
    .{ .name = "ascii", .seed = "The quick brown fox jumps over the lazy dog. ", .length = 96 },
    .{ .name = "combining", .seed = "Cafe\xcc\x81 nai\xcc\x88ve coo\xcc\x88perate. ", .length = 96 },
    .{ .name = "cjk", .seed = "日本語の文章と漢字を測定します。 ", .length = 96 },
    .{ .name = "emoji", .seed = "👩‍👩‍👧‍👦 🇬🇷 👋🏿 ", .length = 96 },
    .{ .name = "malformed", .seed = "valid \xff bytes \xc0\x80 remain bounded ", .length = 96 },
};

/// Word segmentation only. These shapes stress rules the document corpora
/// barely exercise: the WB6/WB12 punctuation bridge and its lookahead across
/// folded runs, the Hebrew quote rules, WB=Other scripts the default rules
/// cannot segment, and malformed bytes at contextual positions.
const word_corpora = [_]Corpus{
    .{ .name = "word-hebrew", .seed = "\u{05E9}\u{05DC}\u{05D5}\u{05DD} \u{05D0}\"\u{05D1} \u{05D2}'\u{05D3} \u{05E2}\u{05D5}\u{05DC}\u{05DD} ", .length = 4096 },
    .{ .name = "word-numeric", .seed = "buy 3.14 or 1,000.50 units at $9.99, 27% off, ref 12.3.4 ", .length = 4096 },
    .{ .name = "word-han", .seed = "\u{65E5}\u{672C}\u{8A9E}\u{306E}\u{6587}\u{7AE0}\u{3068}\u{6F22}\u{5B57}\u{3092}\u{6E2C}\u{5B9A}\u{3057}\u{307E}\u{3059}\u{3002} ", .length = 4096 },
    .{ .name = "word-folded", .seed = "a.\u{0308}\u{0308}\u{0308}b 1,\u{0345}\u{0345}2 x\u{200D}\u{1F600} ", .length = 4096 },
    .{ .name = "word-malformed", .seed = "ok \xff \xc0\x80 a.\xffb 1,\xff2 text ", .length = 4096 },
};

/// Normalization only. `nfc-composed` is already NFC and should take the
/// cheapest path through `is_nfc`; `nfc-maybe` is full of NFC_QC=Maybe marks
/// that the quick check cannot settle by itself, which is the whole reason
/// `isNormalized` is not just a table lookup. `adversarial` needs a canonical
/// reordering on every run, and `at-limit` sits exactly on the configured
/// non-starter limit.
const normalization_corpora = [_]Corpus{
    .{ .name = "nfc-composed", .seed = "Caf\u{00E9} na\u{00EF}ve r\u{00E9}sum\u{00E9} \u{00C5}ngstr\u{00F6}m ", .length = 4096 },
    .{ .name = "nfd-decomposed", .seed = "Cafe\u{0301} nai\u{0308}ve re\u{0301}sume\u{0301} A\u{030A}ngstro\u{0308}m ", .length = 4096 },
    .{ .name = "nfc-maybe", .seed = "e\u{0301}a\u{0300}o\u{0308}u\u{0302}i\u{0303}n\u{0327}c\u{0301} ", .length = 4096 },
    // Already NFC *and* full of NFC_QC=Maybe marks: every one of them has to
    // be settled, and every one settles to "did not compose", so `is_nfc`
    // answers true only after doing the work. `nfc-maybe` above is NFD, so it
    // short-circuits to false on its first mark and measures nothing.
    .{ .name = "nfc-maybe-true", .seed = "z\u{0300}q\u{0300}v\u{0300}w\u{0303}x\u{0300}j\u{0300} ", .length = 4096 },
    .{ .name = "adversarial", .seed = "a\u{0301}\u{0327}\u{0316}\u{0300}\u{031D}\u{0302} ", .length = 4096 },
    .{ .name = "hangul", .seed = "\u{1111}\u{1171}\u{11B6}\u{1100}\u{1161}\u{11A8}\u{D4DB}\u{AC01} ", .length = 4096 },
    .{ .name = "ascii", .seed = "The quick brown fox jumps over the lazy dog. ", .length = 4096 },
};

/// Compatibility-mapping-heavy input for nfkc/nfkd, run through the whole
/// normalization operation set above (nfc/nfd included) so the cost of a
/// compatibility mapping is visible against the canonical forms' cost on the
/// exact same bytes, not just against a different corpus. `max-expansion` is
/// the generated witness (U+FDFA, verified 18 scalars, 11x bytes) repeated,
/// the worst per-byte case rather than an ordinary compatibility-heavy text.
const compat_corpora = [_]Corpus{
    .{ .name = "compat-ligatures", .seed = "o\u{FB03}ce \u{FB01}nd \u{FB02}avor \u{FB00}", .length = 4096 },
    .{ .name = "compat-fullwidth", .seed = "\u{FF21}\u{FF22}\u{FF23}\u{FF11}\u{FF12}\u{FF13} ", .length = 4096 },
    .{ .name = "compat-circled-and-super", .seed = "\u{2460}\u{2461}\u{2462}\u{00B2}\u{00B3}\u{00B9} ", .length = 4096 },
    .{ .name = "max-expansion", .seed = "\u{FDFA}", .length = 4096 },
};

/// Trimming only. These rows are timed per *call*, not per byte: the cost is
/// the whitespace removed plus one bounded look at the first retained scalar,
/// so dividing by input size would describe nothing. They carry
/// `traversal=edges`, `work_bytes` is the call count, and `mib_per_s` is
/// therefore not a throughput -- compare `elapsed_ns` between rows.
///
/// Every case runs the same number of calls, which is what makes the `clean`
/// pair a test rather than a datum: `trim-ascii-64-clean` and
/// `trim-ascii-64k-clean` differ by a factor of 1024 in input size and must
/// take the same time. A large `trim-ascii-64k-clean` would mean something is
/// reading the middle of the input.
const TrimCase = struct {
    name: []const u8,
    prefix: []const u8 = "",
    seed: []const u8,
    length: usize,
    suffix: []const u8 = "",
};

const trim_cases = [_]TrimCase{
    .{ .name = "trim-ascii-64-clean", .seed = "The quick brown fox jumps over the lazy dog. ", .length = 64 },
    .{ .name = "trim-ascii-64-padded", .prefix = "  \t", .seed = "The quick brown fox jumps over the lazy dog. ", .length = 64, .suffix = " \n" },
    .{ .name = "trim-ascii-64k-clean", .seed = "The quick brown fox jumps over the lazy dog. ", .length = 65536 },
    .{ .name = "trim-ascii-64k-padded", .prefix = "  \t", .seed = "The quick brown fox jumps over the lazy dog. ", .length = 65536, .suffix = " \n" },
    // The only rows whose cost really is proportional to the input.
    .{ .name = "trim-all-space-4k", .seed = " ", .length = 4096 },
    .{ .name = "trim-all-unicode-space-4k", .seed = "\u{3000}\u{00A0}\u{2003}\u{205F}", .length = 4096 },
    // Mixed Unicode whitespace: one end, then both.
    .{ .name = "trim-unicode-edge-start", .prefix = "\u{3000}\u{00A0}\u{2003}\u{202F}\u{205F}\u{1680}\u{2028} ", .seed = "\u{65E5}\u{672C}\u{8A9E}\u{306E}\u{6587}\u{7AE0} ", .length = 4096 },
    .{ .name = "trim-unicode-edge-both", .prefix = "\u{3000}\u{00A0}\u{2003}\u{202F}\u{205F}\u{1680}\u{2028} ", .seed = "\u{65E5}\u{672C}\u{8A9E}\u{306E}\u{6587}\u{7AE0} ", .length = 4096, .suffix = " \u{2029}\u{200A}\u{0085}\u{3000}" },
    // Whitespace, then a malformed sequence that has to stop the scan without
    // searching backwards through the run of continuation bytes.
    .{ .name = "trim-malformed-edges", .prefix = "  \xff\xc0\x80", .seed = "ok \xff \xc0\x80 text ", .length = 4096, .suffix = "\xf0\x9f\x98  " },
};

fn makeTrimCorpus(allocator: std.mem.Allocator, case: TrimCase) ![]u8 {
    // Whole seed repetitions only, so a multi-byte scalar is never cut in half.
    const repeats = @max(@as(usize, 1), case.length / case.seed.len);
    const body = case.seed.len * repeats;
    const text = try allocator.alloc(u8, case.prefix.len + body + case.suffix.len);
    @memcpy(text[0..case.prefix.len], case.prefix);
    for (0..repeats) |index|
        @memcpy(text[case.prefix.len + index * case.seed.len ..][0..case.seed.len], case.seed);
    @memcpy(text[case.prefix.len + body ..], case.suffix);
    return text;
}

const wrap_cases = [_]WrapCase{
    .{ .name = "ascii-words-4k-grapheme-full", .corpus = .{ .name = "ascii-words", .seed = "alpha beta gamma delta epsilon zeta eta theta ", .length = 4096 }, .max_columns = 40, .overflow = .grapheme },
    .{ .name = "ascii-words-4k-allow-full", .corpus = .{ .name = "ascii-words", .seed = "alpha beta gamma delta epsilon zeta eta theta ", .length = 4096 }, .max_columns = 40, .overflow = .allow },
    .{ .name = "prose-64-grapheme-full", .corpus = .{ .name = "prose", .seed = "A paragraph has spaces, punctuation, numbers 123, and quoted words. ", .length = 96 }, .max_columns = 1, .overflow = .grapheme },
    .{ .name = "prose-4k-allow-full", .corpus = .{ .name = "prose", .seed = "A paragraph has spaces, punctuation, numbers 123, and quoted words. ", .length = 4096 }, .max_columns = 40, .overflow = .allow },
    .{ .name = "greek-4k-grapheme-full", .corpus = .{ .name = "greek", .seed = "Καλημέρα cafe\xcc\x81 — λέξεις και τόνοι. ", .length = 4096 }, .max_columns = 80, .overflow = .grapheme },
    .{ .name = "cjk-4k-allow-full", .corpus = .{ .name = "cjk", .seed = "日本語の文章と漢字を測定します。 ", .length = 4096 }, .max_columns = 40, .overflow = .allow },
    .{ .name = "emoji-4k-grapheme-24-lines", .corpus = .{ .name = "emoji", .seed = "👩‍👩‍👧‍👦 🇬🇷 👋🏿 ", .length = 4096 }, .max_columns = 40, .overflow = .grapheme, .max_lines = 24 },
    .{ .name = "hard-breaks-4k-allow-24-lines", .corpus = .{ .name = "hard", .seed = "alpha\nβeta\x0c界\xc2\x85emoji👩‍👩‍👧‍👦 ", .length = 4096 }, .max_columns = 80, .overflow = .allow, .max_lines = 24 },
    .{ .name = "ascii-text-4k-grapheme-full", .corpus = .{ .name = "ascii-text", .seed = "the 3 quick brown foxes don't jump over 27 lazy dogs ", .length = 4096 }, .max_columns = 40, .overflow = .grapheme },
    .{ .name = "long-word-4k-grapheme-full", .corpus = .{ .name = "word", .seed = "supercalifragilisticexpialidocious", .length = 4096 }, .max_columns = 40, .overflow = .grapheme },
    .{ .name = "zero-width-4k-allow-full", .corpus = .{ .name = "zero", .seed = "e\xcc\x81\xcc\x81\xcc\x81\xcc\x81", .length = 4096 }, .max_columns = 1, .overflow = .allow },
    .{ .name = "malformed-4k-grapheme-full", .corpus = .{ .name = "malformed", .seed = "ok \xff \xc0\x80 text ", .length = 4096 }, .max_columns = 40, .overflow = .grapheme },
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    var smoke = false;
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--smoke")) smoke = true;
    }
    if (args.len > 1 and std.mem.eql(u8, args[1], "--corpus-stats")) {
        var stats_buffer: [4096]u8 = undefined;
        var stats_file = std.Io.File.stdout().writer(io, &stats_buffer);
        try printCorpusStats(&stats_file.interface, allocator);
        return stats_file.interface.flush();
    }
    const target_bytes: usize = if (smoke) 64 * 1024 else 4 * 1024 * 1024;
    var output_buffer: [4096]u8 = undefined;
    var output_file = std.Io.File.stdout().writer(io, &output_buffer);
    const output = &output_file.interface;
    try output.print("zunic-benchmark harness_version={s} target_bytes={d} samples={d} smoke={any} wrap_fast_path={s} line_break_engine=machine scope=all\n", .{ harness_version, target_bytes, sample_count, smoke, @tagName(zunic.build_options.wrap_fast_path) });
    for (legacy_corpora) |corpus| {
        const text = try makeCorpus(allocator, corpus);
        try printSamples(output, corpus.name, "utf8", text, target_bytes, utf8Checksum, io);
        try printSamples(output, corpus.name, "grapheme", text, target_bytes, graphemeChecksum, io);
        try printSamples(output, corpus.name, "measured", text, target_bytes, measuredChecksum, io);
        try printSamples(output, corpus.name, "width", text, target_bytes, widthChecksum, io);
        try printSamples(output, corpus.name, "line_break", text, target_bytes, lineBreakChecksum, io);
        try printSamples(output, corpus.name, "terminators", text, target_bytes, terminatorChecksum, io);
        try printSamples(output, corpus.name, "word_bounds", text, target_bytes, wordChecksum, io);
    }
    for (word_corpora) |corpus| {
        const text = try makeCorpus(allocator, corpus);
        try printSamples(output, corpus.name, "word_bounds", text, target_bytes, wordChecksum, io);
    }
    for (normalization_corpora) |corpus| {
        const name = try std.fmt.allocPrint(allocator, "norm-{s}", .{corpus.name});
        const text = try makeCorpus(allocator, corpus);
        try printSamples(output, name, "nfc", text, target_bytes, nfcChecksum, io);
        try printSamples(output, name, "nfd", text, target_bytes, nfdChecksum, io);
        try printSamples(output, name, "nfc_iterate", text, target_bytes, nfcIterateChecksum, io);
        try printSamples(output, name, "is_nfc", text, target_bytes, isNfcChecksum, io);
        try printSamples(output, name, "nfc_quick", text, target_bytes, nfcQuickChecksum, io);
        try printSamples(output, name, "nfd_quick", text, target_bytes, nfdQuickChecksum, io);
        try printSamples(output, name, "eql", text, target_bytes, eqlChecksum, io);
        try printSamples(output, name, "nfkc", text, target_bytes, nfkcChecksum, io);
        try printSamples(output, name, "nfkd", text, target_bytes, nfkdChecksum, io);
        try printSamples(output, name, "is_nfkc", text, target_bytes, isNfkcChecksum, io);
        try printSamples(output, name, "nfkc_quick", text, target_bytes, nfkcQuickChecksum, io);
        try printSamples(output, name, "nfkd_quick", text, target_bytes, nfkdQuickChecksum, io);
        try printSamples(output, name, "eql_compat", text, target_bytes, eqlCompatChecksum, io);
    }
    for (compat_corpora) |corpus| {
        const name = try std.fmt.allocPrint(allocator, "norm-{s}", .{corpus.name});
        const text = try makeCorpus(allocator, corpus);
        try printSamples(output, name, "nfc", text, target_bytes, nfcChecksum, io);
        try printSamples(output, name, "nfd", text, target_bytes, nfdChecksum, io);
        try printSamples(output, name, "nfkc", text, target_bytes, nfkcChecksum, io);
        try printSamples(output, name, "nfkd", text, target_bytes, nfkdChecksum, io);
        try printSamples(output, name, "is_nfkc", text, target_bytes, isNfkcChecksum, io);
        try printSamples(output, name, "nfkc_quick", text, target_bytes, nfkcQuickChecksum, io);
        try printSamples(output, name, "nfkd_quick", text, target_bytes, nfkdQuickChecksum, io);
        try printSamples(output, name, "eql_compat", text, target_bytes, eqlCompatChecksum, io);
    }
    try runAsciiCases(output, allocator, target_bytes, io);
    // Scaled off target_bytes so `--smoke` stays quick; a byte budget would
    // give the 64 KB rows too few calls to time.
    const trim_calls = @max(@as(usize, 1024), target_bytes / 64);
    for (trim_cases) |case| {
        const text = try makeTrimCorpus(allocator, case);
        try printTrimSamples(output, case.name, "trim", text, trim_calls, trimChecksum, io);
        try printTrimSamples(output, case.name, "trim_start", text, trim_calls, trimStartChecksum, io);
        try printTrimSamples(output, case.name, "trim_end", text, trim_calls, trimEndChecksum, io);
    }
    for (wrap_cases) |case| try printWrapSamples(output, case, try makeCorpus(allocator, case.corpus), target_bytes, io);
    try runDocumentCorpora(output, allocator, target_bytes, io);
    try output.flush();
}

/// Expand a generated statistical profile into a deterministic document.
///
/// The repeated-seed corpora above are 4 KB of one short seed: a handful of
/// property-table blocks stay resident in L1 and the branch predictor learns
/// the cycle, so they cannot show a lost prefetch or a lookup miss. These
/// profiles reproduce the code-point spread, word lengths and line lengths of
/// real documents at document size, which can. See plans/017.
///
/// Deterministic across platforms: fixed seed, fixed algorithm. Generation
/// happens once, before timing.
fn Profile(comptime P: type) type {
    return struct {
        fn pick(random: std.Random, keys: anytype, cum: []const u32) @TypeOf(keys[0]) {
            const roll = random.uintLessThan(u32, cum[cum.len - 1]) + 1;
            var low: usize = 0;
            var high: usize = cum.len - 1;
            while (low < high) {
                const mid = low + (high - low) / 2;
                if (cum[mid] < roll) low = mid + 1 else high = mid;
            }
            return keys[low];
        }

        fn isMark(cp: u21) bool {
            for (P.marks) |m| if (m == cp) return true;
            return false;
        }

        fn generate(allocator: std.mem.Allocator, target_bytes: usize) ![]u8 {
            var prng = std.Random.DefaultPrng.init(0x2075_c0_11ec7);
            const random = prng.random();
            var out: std.ArrayList(u8) = .empty;
            errdefer out.deinit(allocator);
            var encoded: [4]u8 = undefined;
            var column: usize = 0;
            var line_target = pick(random, &P.lines_keys, &P.lines_cum);
            while (out.items.len < target_bytes) {
                const word_len = pick(random, &P.words_keys, &P.words_cum);
                var emitted: usize = 0;
                var previous_is_break = true;
                while (emitted < word_len) : (emitted += 1) {
                    var cp = pick(random, &P.chars_keys, &P.chars_cum);
                    // A combining mark never opens a cluster in real text;
                    // resample so cluster counts stay representative.
                    var guard: usize = 0;
                    while (previous_is_break and isMark(cp) and guard < 8) : (guard += 1)
                        cp = pick(random, &P.chars_keys, &P.chars_cum);
                    if (previous_is_break and isMark(cp)) continue;
                    const len = std.unicode.utf8Encode(cp, &encoded) catch continue;
                    try out.appendSlice(allocator, encoded[0..len]);
                    previous_is_break = false;
                    column += 1;
                    // Scripts without spaces (CJK) produce very long "words",
                    // so the line target has to be honoured inside a word too
                    // or line structure drifts far from the profile.
                    if (column >= line_target) break;
                }
                if (column >= line_target) {
                    try out.append(allocator, '\n');
                    column = 0;
                    line_target = pick(random, &P.lines_keys, &P.lines_cum);
                } else {
                    try out.append(allocator, ' ');
                    column += 1;
                }
            }
            return out.toOwnedSlice(allocator);
        }
    };
}

const document_bytes = 50 * 1024;

/// Report what the generated documents actually look like, so their fidelity
/// to the reference profiles can be checked without shipping the references.
fn printCorpusStats(output: *std.Io.Writer, allocator: std.mem.Allocator) !void {
    inline for (.{
        .{ "arabic", corpora.arabic },   .{ "english", corpora.english },
        .{ "hindi", corpora.hindi },     .{ "japanese", corpora.japanese },
        .{ "korean", corpora.korean },   .{ "mandarin", corpora.mandarin },
        .{ "russian", corpora.russian }, .{ "source_code", corpora.source_code },
    }) |entry| {
        const text = try Profile(entry[1]).generate(allocator, document_bytes);
        var clusters: usize = 0;
        var it = zunic.text(text).graphemes().iterator();
        while (it.next() != null) clusters += 1;
        var lines: usize = 0;
        for (text) |b| {
            if (b == '\n') lines += 1;
        }
        var scalars: usize = 0;
        var pos: usize = 0;
        while (pos < text.len) : (scalars += 1) pos += zunic.utf8.step(text[pos..]).len;
        try output.print(
            "corpus={s} bytes={d} scalars={d} clusters={d} lines={d} bytes_per_cluster={d:.2} width={d}\n",
            .{ entry[0], text.len, scalars, clusters, lines, @as(f64, @floatFromInt(text.len)) / @as(f64, @floatFromInt(clusters)), zunic.text(text).width() },
        );
    }
}

/// Every generated document runs the same operation set as the legacy corpora,
/// plus a wrap at 80 columns. Case names are prefixed `doc-` so they never
/// collide with the repeated-seed cases.
fn runDocumentCorpora(output: *std.Io.Writer, allocator: std.mem.Allocator, target_bytes: usize, io: std.Io) !void {
    inline for (.{
        .{ "arabic", corpora.arabic },   .{ "english", corpora.english },
        .{ "hindi", corpora.hindi },     .{ "japanese", corpora.japanese },
        .{ "korean", corpora.korean },   .{ "mandarin", corpora.mandarin },
        .{ "russian", corpora.russian }, .{ "source_code", corpora.source_code },
    }) |entry| {
        const name = "doc-" ++ entry[0];
        const text = try Profile(entry[1]).generate(allocator, document_bytes);
        try printSamples(output, name, "grapheme", text, target_bytes, graphemeChecksum, io);
        try printSamples(output, name, "measured", text, target_bytes, measuredChecksum, io);
        try printSamples(output, name, "width", text, target_bytes, widthChecksum, io);
        try printSamples(output, name, "line_break", text, target_bytes, lineBreakChecksum, io);
        try printSamples(output, name, "terminators", text, target_bytes, terminatorChecksum, io);
        try printSamples(output, name, "word_bounds", text, target_bytes, wordChecksum, io);
        try printWrapSamples(output, .{
            .name = name,
            .corpus = .{ .name = name, .seed = "", .length = 0 },
            .max_columns = 80,
            .overflow = .grapheme,
        }, text, target_bytes, io);
    }
}

fn makeCorpus(allocator: std.mem.Allocator, corpus: Corpus) ![]u8 {
    const text = try allocator.alloc(u8, corpus.length);
    for (text, 0..) |*byte, index| byte.* = corpus.seed[index % corpus.seed.len];
    return text;
}

fn printSamples(output: *std.Io.Writer, corpus: []const u8, operation: []const u8, text: []u8, target_bytes: usize, comptime checksumFn: fn ([]const u8) u64, io: std.Io) !void {
    const iterations = @max(@as(usize, 1), target_bytes / text.len);
    std.mem.doNotOptimizeAway(checksumFn(text));
    for (0..sample_count) |_| {
        const start = std.Io.Clock.Timestamp.now(io, .awake);
        var checksum: u64 = 0;
        for (0..iterations) |_| {
            std.mem.doNotOptimizeAway(text);
            checksum +%= checksumFn(text);
        }
        std.mem.doNotOptimizeAway(checksum);
        const elapsed = start.durationTo(std.Io.Clock.Timestamp.now(io, .awake)).raw.toNanoseconds();
        try printSample(output, corpus, operation, "full", text.len, iterations, elapsed, checksum, text.len * iterations, null, null);
    }
}

/// Fixed call count, so `elapsed_ns` is comparable across inputs of different
/// sizes. See the `trim_cases` comment for why bytes are the wrong denominator.
fn printTrimSamples(output: *std.Io.Writer, case: []const u8, operation: []const u8, text: []u8, calls: usize, comptime checksumFn: fn ([]const u8) u64, io: std.Io) !void {
    std.mem.doNotOptimizeAway(checksumFn(text));
    for (0..sample_count) |_| {
        const start = std.Io.Clock.Timestamp.now(io, .awake);
        var checksum: u64 = 0;
        for (0..calls) |_| {
            std.mem.doNotOptimizeAway(text);
            checksum +%= checksumFn(text);
        }
        std.mem.doNotOptimizeAway(checksum);
        const elapsed = start.durationTo(std.Io.Clock.Timestamp.now(io, .awake)).raw.toNanoseconds();
        try printSample(output, case, operation, "edges", text.len, calls, elapsed, checksum, calls, null, null);
    }
}

fn printWrapSamples(output: *std.Io.Writer, case: WrapCase, text: []u8, target_bytes: usize, io: std.Io) !void {
    const iterations = @max(@as(usize, 1), target_bytes / text.len);
    std.mem.doNotOptimizeAway(wrapChecksum(text, case));
    for (0..sample_count) |_| {
        const start = std.Io.Clock.Timestamp.now(io, .awake);
        var checksum: u64 = 0;
        var lines: usize = 0;
        var emitted: usize = 0;
        for (0..iterations) |_| {
            const result = wrapChecksum(text, case);
            checksum +%= result.checksum;
            lines += result.lines;
            emitted += result.emitted_bytes;
        }
        std.mem.doNotOptimizeAway(checksum);
        const elapsed = start.durationTo(std.Io.Clock.Timestamp.now(io, .awake)).raw.toNanoseconds();
        try printSample(output, case.name, "wrap", if (case.max_lines == null) "full" else "viewport", text.len, iterations, elapsed, checksum, emitted, lines, case.max_columns);
    }
}

fn printSample(output: *std.Io.Writer, case: []const u8, operation: []const u8, traversal: []const u8, input_bytes: usize, iterations: usize, elapsed_ns: i96, checksum: u64, work_bytes: usize, lines: ?usize, max_columns: ?usize) !void {
    const rate: f64 = if (elapsed_ns <= 0) 0 else @as(f64, @floatFromInt(work_bytes)) / 1048576.0 / (@as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0);
    try output.print("case={s} operation={s} traversal={s} input_bytes={d} iterations={d} work_bytes={d} elapsed_ns={d} checksum={d} mib_per_s={d:.2}", .{ case, operation, traversal, input_bytes, iterations, work_bytes, elapsed_ns, checksum, rate });
    if (lines) |value| try output.print(" lines={d}", .{value});
    if (max_columns) |value| try output.print(" max_columns={d}", .{value});
    try output.writeAll("\n");
}

fn mix(state: u64, value: u64) u64 {
    return (state ^ (value +% 0x9e3779b97f4a7c15)) *% 0xbf58476d1ce4e5b9;
}
fn utf8Checksum(text: []const u8) u64 {
    var pos: usize = 0;
    var sum: u64 = 0xcbf29ce484222325;
    while (pos < text.len) {
        const step = zunic.utf8.step(text[pos..]);
        sum = mix(sum, step.len);
        sum = mix(sum, step.cp orelse 0xffff_ffff);
        pos += step.len;
    }
    return sum;
}
fn graphemeChecksum(text: []const u8) u64 {
    var it = zunic.text(text).graphemes().iterator();
    var sum: u64 = 0xcbf29ce484222325;
    while (it.next()) |span| {
        sum = mix(sum, span.start.value);
        sum = mix(sum, span.end.value);
    }
    return sum;
}
/// Walks the measured grapheme traversal, the only public path that reports
/// per-cluster columns and renderability. Nothing else in this harness
/// observes `MeasuredGraphemes`.
fn measuredChecksum(text: []const u8) u64 {
    var it = zunic.text(text).graphemes().measured().iterator();
    var sum: u64 = 0xcbf29ce484222325;
    while (it.next()) |span| {
        sum = mix(sum, span.start.value);
        sum = mix(sum, span.end.value);
        sum = mix(sum, span.columns);
        sum = mix(sum, @intFromBool(span.renderable));
    }
    return sum;
}
fn widthChecksum(text: []const u8) u64 {
    return mix(0xcbf29ce484222325, zunic.text(text).width());
}
fn lineBreakChecksum(text: []const u8) u64 {
    var it = zunic.line_break.iterator(text);
    var sum: u64 = 0xcbf29ce484222325;
    while (it.next()) |boundary| {
        sum = mix(sum, boundary.offset);
        sum = mix(sum, @intFromEnum(boundary.opportunity));
    }
    return sum;
}
fn terminatorChecksum(text: []const u8) u64 {
    var it = zunic.text(text).terminators().iterator();
    var sum: u64 = 0xcbf29ce484222325;
    while (it.next()) |t| {
        sum = mix(sum, t.start.value);
        sum = mix(sum, t.end.value);
    }
    return sum;
}
/// Normalization can legitimately fail on a corpus -- `malformed` is not
/// UTF-8, and an over-long run is rejected by design -- so the error is folded
/// into the checksum instead of ending the run. A peer that starts failing
/// where it used to succeed changes the checksum and is caught.
var normalization_buffer: [512 * 1024]u8 = undefined;

fn failureCode(err: anyerror) u64 {
    return switch (err) {
        error.InvalidUtf8 => 1,
        error.SequenceTooLong => 2,
        error.NoSpace => 3,
        else => 4,
    };
}

fn writeChecksum(text: []const u8, comptime form: zunic.Form) u64 {
    const written = zunic.text(text).normalize(form).writeTo(&normalization_buffer) catch |err|
        return mix(0xcbf29ce484222325, failureCode(err));
    var sum: u64 = 0xcbf29ce484222325;
    for (written) |byte| sum = mix(sum, byte);
    return mix(sum, written.len);
}
fn nfcChecksum(text: []const u8) u64 {
    return writeChecksum(text, .nfc);
}
fn nfdChecksum(text: []const u8) u64 {
    return writeChecksum(text, .nfd);
}
fn nfkcChecksum(text: []const u8) u64 {
    return writeChecksum(text, .nfkc);
}
fn nfkdChecksum(text: []const u8) u64 {
    return writeChecksum(text, .nfkd);
}
/// Scalar-at-a-time traversal, with no encoding and no destination buffer.
fn nfcIterateChecksum(text: []const u8) u64 {
    var it = zunic.text(text).normalize(.nfc);
    var sum: u64 = 0xcbf29ce484222325;
    while (it.next() catch |err| return mix(sum, failureCode(err))) |cp| sum = mix(sum, cp);
    return sum;
}
/// The three-valued quick check, which settles nothing.
fn quickChecksum(text: []const u8, comptime form: zunic.Form) u64 {
    const answer = zunic.text(text).isNormalizedQuick(form) catch |err|
        return mix(0xcbf29ce484222325, failureCode(err));
    return mix(0xcbf29ce484222325, @intFromEnum(answer));
}
fn nfcQuickChecksum(text: []const u8) u64 {
    return quickChecksum(text, .nfc);
}
fn nfdQuickChecksum(text: []const u8) u64 {
    return quickChecksum(text, .nfd);
}
fn nfkcQuickChecksum(text: []const u8) u64 {
    return quickChecksum(text, .nfkc);
}
fn nfkdQuickChecksum(text: []const u8) u64 {
    return quickChecksum(text, .nfkd);
}
fn isNfcChecksum(text: []const u8) u64 {
    const answer = zunic.text(text).isNormalized(.nfc) catch |err|
        return mix(0xcbf29ce484222325, failureCode(err));
    return mix(0xcbf29ce484222325, @intFromBool(answer));
}
fn isNfkcChecksum(text: []const u8) u64 {
    const answer = zunic.text(text).isNormalized(.nfkc) catch |err|
        return mix(0xcbf29ce484222325, failureCode(err));
    return mix(0xcbf29ce484222325, @intFromBool(answer));
}
/// Comparing a corpus with itself: the case that has to traverse both operands
/// to the end rather than stopping at the first difference.
fn eqlChecksum(text: []const u8) u64 {
    const answer = zunic.text(text).eql(text, .canonical) catch |err|
        return mix(0xcbf29ce484222325, failureCode(err));
    return mix(0xcbf29ce484222325, @intFromBool(answer));
}
fn eqlCompatChecksum(text: []const u8) u64 {
    const answer = zunic.text(text).eql(text, .compatibility) catch |err|
        return mix(0xcbf29ce484222325, failureCode(err));
    return mix(0xcbf29ce484222325, @intFromBool(answer));
}

/// All three item fields, so a boundary shift and a flag error are both
/// visible in the checksum.
/// A false answer can stop at the first high byte; a true answer must scan
/// every byte. `ascii-high-byte-start` and `ascii-high-byte-end` bracket
/// that: one exits after the first vector chunk, the other only after
/// scanning the whole slice, so a regression that lost the early exit shows
/// up as `ascii-high-byte-start` drifting toward `ascii-long`'s rate rather
/// than `ascii-high-byte-end`'s.
fn runAsciiCases(output: *std.Io.Writer, allocator: std.mem.Allocator, target_bytes: usize, io: std.Io) !void {
    const short = try makeCorpus(allocator, .{ .name = "ascii-short", .seed = "The quick brown fox jumps over the lazy dog. ", .length = 96 });
    try printSamples(output, "ascii-short", "is_ascii", short, target_bytes, asciiChecksum, io);

    const long = try makeCorpus(allocator, .{ .name = "ascii-long", .seed = "The quick brown fox jumps over the lazy dog. ", .length = 65536 });
    try printSamples(output, "ascii-long", "is_ascii", long, target_bytes, asciiChecksum, io);

    const high_start = try allocator.alloc(u8, 65536);
    @memset(high_start, 'a');
    high_start[0] = 0x80;
    try printSamples(output, "ascii-high-byte-start", "is_ascii", high_start, target_bytes, asciiChecksum, io);

    const high_end = try allocator.alloc(u8, 65536);
    @memset(high_end, 'a');
    high_end[high_end.len - 1] = 0x80;
    try printSamples(output, "ascii-high-byte-end", "is_ascii", high_end, target_bytes, asciiChecksum, io);
}

/// The public entry point, same as any real caller reaches for.
fn asciiChecksum(text: []const u8) u64 {
    return mix(0xcbf29ce484222325, @intFromBool(zunic.text(text).isAscii()));
}

fn wordChecksum(text: []const u8) u64 {
    var it = zunic.text(text).wordBounds().iterator();
    var sum: u64 = 0xcbf29ce484222325;
    while (it.next()) |segment| {
        sum = mix(sum, segment.start.value);
        sum = mix(sum, segment.end.value);
        sum = mix(sum, @intFromBool(segment.is_word));
    }
    return sum;
}
/// The retained slice's offset and length, and nothing else. Hashing the
/// retained body would add a full pass over bytes trimming never reads, hiding
/// the edge-only cost these rows exist to show.
inline fn retainedChecksum(result: zunic.Text, text: []const u8) u64 {
    const start = @intFromPtr(result.bytes.ptr) - @intFromPtr(text.ptr);
    return mix(mix(0xcbf29ce484222325, start), result.bytes.len);
}
fn trimChecksum(text: []const u8) u64 {
    return retainedChecksum(zunic.text(text).trim(), text);
}
fn trimStartChecksum(text: []const u8) u64 {
    return retainedChecksum(zunic.text(text).trimStart(), text);
}
fn trimEndChecksum(text: []const u8) u64 {
    return retainedChecksum(zunic.text(text).trimEnd(), text);
}
const WrapResult = struct { checksum: u64, lines: usize, emitted_bytes: usize };
fn wrapChecksum(text: []const u8, case: WrapCase) WrapResult {
    var wrapped = zunic.text(text).wrap(.{ .max_columns = case.max_columns, .overflow = case.overflow }) catch unreachable;
    var it = wrapped.iterator();
    var sum: u64 = 0xcbf29ce484222325;
    var lines: usize = 0;
    var emitted: usize = 0;
    while (it.next()) |line| {
        sum = mix(sum, line.start.value);
        sum = mix(sum, line.end.value);
        sum = mix(sum, line.columns.value);
        lines += 1;
        emitted += line.end.value - line.start.value;
        if (case.max_lines) |limit| if (lines == limit) break;
    }
    return .{ .checksum = sum, .lines = lines, .emitted_bytes = emitted };
}
