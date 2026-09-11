//! All four Unicode 17.0 normalization forms (UAX #15): NFC, NFD, NFKC, NFKD.
//!
//! Canonical and compatibility decomposition are read from separate generated
//! tables (see `src/tables/normalization_properties.zig`): canonical mappings
//! are at most two scalars immediate, compatibility mappings run up to 18
//! (U+FDFA). NFKC composes with exactly the same canonical composition pairs
//! and exclusions as NFC; a compatibility mapping is never rebuilt by
//! composition, in either direction.
//!
//! Compatibility equivalence is an explicit, narrower guarantee than
//! canonical equivalence: `U+FB01` and `"fi"` are compatibility-equivalent
//! but not canonically equivalent, and the two are never confused by a
//! default -- a caller chooses `.canonical` or `.compatibility` explicitly.
//!
//! Nothing here allocates. The working buffer is inline and its size is a
//! compile-time module setting, `-Dnormalization-buffer-bytes`, so a combining
//! sequence longer than the configured limit is rejected with
//! `error.SequenceTooLong` rather than truncated, silently reordered, or
//! quietly declared equal to something else. This limit is unrelated to how
//! far a single scalar's own decomposition can spread (four entries for a
//! canonical form, at most `properties.max_compat_expansion` for a
//! compatibility one): those are pulled into the run one entry at a time, so
//! a long *decomposition* streams through the same limit a long run of
//! *combining marks* does, rather than being rejected outright for its size.
//!
//! Unlike the rest of the package, normalization is **strict about malformed
//! UTF-8**: an invalid encoding is `error.InvalidUtf8`, never a replacement
//! character and never a skipped byte. Two different invalid inputs must not
//! be able to compare equal by both decaying to U+FFFD. Grapheme, word,
//! width, wrapping and `utf8.step` keep their tolerant behaviour.
const std = @import("std");
const build_options = @import("build_options");
const utf8 = @import("encoding").utf8;
const properties = @import("tables").normalization;

pub const Form = enum { nfc, nfd, nfkc, nfkd };
pub const Equivalence = enum { canonical, compatibility };
/// Defined once, by the table generator, and re-exported here and from
/// `root.zig` so the tags are not written down twice.
pub const QuickCheck = properties.QuickCheck;

pub const Error = error{ InvalidUtf8, SequenceTooLong };
pub const WriteError = Error || error{NoSpace};

/// Working buffer for one iterator, in bytes. See `-Dnormalization-buffer-bytes`.
pub const buffer_bytes: usize = build_options.normalization_buffer_bytes;
pub const buffer_entries: usize = buffer_bytes / @sizeOf(Entry);
/// The longest run of non-starters this build accepts, counted after full
/// decomposition. Two entries are headroom: the starter that opens the run,
/// and one spare.
pub const max_nonstarters: usize = buffer_entries - 2;
// Include the length as well as every index, at any supported buffer size.
const RunLength = std.math.IntFittingRange(0, buffer_entries);

comptime {
    if (buffer_bytes == 0 or buffer_bytes % 32 != 0)
        @compileError("normalization-buffer-bytes must be a positive multiple of 32");
    if (@sizeOf(Entry) != 4) @compileError("Entry must be four bytes");
}

/// One decomposed scalar with everything the run machinery asks about it.
///
/// `base` and `composable` are the two halves of the composition question, so
/// a pair that cannot possibly compose is rejected on two register bits
/// instead of a search through hundreds of pairs. Both include Hangul, which
/// composes arithmetically and appears in no table.
const Entry = packed struct(u32) {
    scalar: u21,
    ccc: u8,
    base: bool,
    composable: bool,
    _padding: u1 = 0,
};

// UAX #15 section 16. These are the only mappings zunic computes rather than
// stores; the generated tables deliberately contain no Hangul, for either form.
const s_base = 0xAC00;
const l_base = 0x1100;
const v_base = 0x1161;
const t_base = 0x11A7;
const l_count = 19;
const v_count = 21;
const t_count = 28;
const n_count = v_count * t_count;
const s_count = l_count * n_count;

/// True for `.nfkc` and `.nfkd`: the two forms that also consult
/// compatibility mappings, not just canonical ones.
fn isCompat(comptime form: Form) bool {
    return form == .nfkc or form == .nfkd;
}

/// True for `.nfc` and `.nfkc`: the two forms that canonically compose.
fn isCompose(comptime form: Form) bool {
    return form == .nfc or form == .nfkc;
}

/// The per-scalar scratch capacity a form needs: four for a canonical form
/// (measured maximum over the pinned data, checked by
/// `test-normalization-properties.py`), or `properties.max_compat_expansion`
/// for a compatibility one (same proof, generated rather than copied by hand
/// since 18 is a much less memorable number than four).
fn scratchLen(comptime form: Form) usize {
    return if (isCompat(form)) properties.max_compat_expansion else 4;
}

/// Full decomposition of one scalar into at most `scratchLen(compatibility
/// form)` entries, canonical or compatibility depending on `compat`.
///
/// A compatibility mapping, where `compat` is true and one exists, is used
/// *instead of* the canonical mapping, never alongside it: the two are
/// mutually exclusive per code point in the source data, so there is no
/// ordering question. Recursion still applies either way.
fn decomposeInto(out: []Entry, cp: u21, comptime compat: bool) u8 {
    // One class lookup answers the common case outright. Before this, every
    // character bisected a decomposition table to be told it has none.
    const class = properties.classOf(cp);
    if (compat and class.compat_decomposes) {
        const mapping = properties.compatDecomposition(cp).?;
        var len: u8 = 0;
        for (mapping) |scalar| len += decomposeInto(out[len..], @intCast(scalar), compat);
        return len;
    }
    if (!class.decomposes) {
        out[0] = .{
            .scalar = cp,
            .ccc = class.ccc,
            .base = class.composition_base,
            .composable = class.composable,
        };
        return 1;
    }
    if (cp >= s_base and cp < s_base + s_count) {
        const index = cp - s_base;
        out[0] = entryOf(@intCast(l_base + index / n_count));
        out[1] = entryOf(@intCast(v_base + (index % n_count) / t_count));
        if (index % t_count == 0) return 2;
        out[2] = entryOf(@intCast(t_base + index % t_count));
        return 3;
    }
    const mapping = properties.decomposition(cp).?;
    var len: u8 = 0;
    for (mapping.scalars) |scalar| len += decomposeInto(out[len..], @intCast(scalar), compat);
    return len;
}

fn entryOf(cp: u21) Entry {
    const class = properties.classOf(cp);
    return .{
        .scalar = cp,
        .ccc = class.ccc,
        .base = class.composition_base,
        .composable = class.composable,
    };
}

/// The primary composite of two scalars, Hangul included. Shared by NFC and
/// NFKC: compatibility mappings are never recomposed.
fn composePair(first: u21, second: u21) ?u21 {
    if (first >= l_base and first < l_base + l_count and
        second >= v_base and second < v_base + v_count)
    {
        return @intCast(s_base + ((first - l_base) * v_count + (second - v_base)) * t_count);
    }
    // T jamo attach to an LV syllable only. U+11A7 is the filler, not a T.
    if (first >= s_base and first < s_base + s_count and (first - s_base) % t_count == 0 and
        second > t_base and second < t_base + t_count)
    {
        return @intCast(first + (second - t_base));
    }
    return properties.compose(first, second);
}

/// Canonical ordering: a stable insertion sort of the non-starters by
/// combining class. Bounded by the configured run limit, so the worst case is
/// `max_nonstarters` squared per run and linear in the input overall.
fn canonicalOrder(run: []Entry) void {
    var i: usize = 1;
    while (i < run.len) : (i += 1) {
        const held = run[i];
        if (held.ccc == 0) continue;
        var j = i;
        // Stop at the starter, and use a strict comparison so equal classes
        // keep their original order.
        while (j > 0 and run[j - 1].ccc != 0 and run[j - 1].ccc > held.ccc) : (j -= 1)
            run[j] = run[j - 1];
        run[j] = held;
    }
}

/// Canonical composition within one ordered run, returning its new length.
///
/// A character is blocked from the starter when a retained character between
/// them has a combining class at least as large. The run is already ordered,
/// so the retained classes are non-decreasing and only the last one matters.
fn composeRun(run: []Entry) RunLength {
    if (run.len == 0 or run[0].ccc != 0) return @intCast(run.len);
    var write: usize = 1;
    // -1 means "nothing retained yet", so the next character sits directly
    // against the starter and cannot be blocked.
    var last_ccc: i16 = -1;
    var i: usize = 1;
    while (i < run.len) : (i += 1) {
        const current = run[i];
        // Two register bits before any search: a pair composes only when the
        // first can absorb and the second can be absorbed.
        if (run[0].base and current.composable and last_ccc < @as(i16, current.ccc)) {
            if (composePair(run[0].scalar, current.scalar)) |composed| {
                run[0].scalar = composed;
                continue;
            }
        }
        last_ccc = current.ccc;
        run[write] = current;
        write += 1;
    }
    return @intCast(write);
}

/// Open a normalizing iterator over borrowed bytes. Construction scans
/// nothing and validates nothing; `next` reports the first problem it reaches.
pub fn normalize(bytes: []const u8, comptime form: Form) Iterator(form) {
    return .{ .bytes = bytes };
}

/// An upper bound on the UTF-8 length of `form` applied to `input_len` bytes.
/// The factor is derived from the pinned data during generation.
///
/// This depends only on a byte count, so it cannot detect malformed UTF-8 or
/// an over-long combining sequence: a buffer of this size rules out
/// `error.NoSpace` and nothing else.
pub fn normalizedLenBound(input_len: usize, comptime form: Form) error{Overflow}!usize {
    // NFD and NFC both reach 3x growth; NFD decomposes the excluded U+1D160
    // into three supplementary musical symbols, four UTF-8 bytes into twelve.
    // NFKD and NFKC both reach 11x, at an 18-scalar Arabic ligature; NFKC
    // shares NFKD's bound rather than getting its own, the same way NFC
    // shares NFD's -- composition only shrinks or holds byte length, proved
    // once in the generator rather than for each composing form.
    const factor = switch (form) {
        .nfc, .nfd => properties.expansion_factor,
        .nfkc, .nfkd => properties.compat_expansion_factor,
    };
    return std.math.mul(usize, input_len, factor);
}

pub fn Iterator(comptime form: Form) type {
    return struct {
        const Self = @This();
        const compat = isCompat(form);
        const compose = isCompose(form);

        bytes: []const u8,
        /// Next input byte to decode.
        pos: usize = 0,

        /// The run being accumulated, or the finished run being drained.
        /// Never more than one starter plus `max_nonstarters` non-starters.
        buffer: [buffer_entries]Entry = undefined,
        len: RunLength = 0,
        emitted: RunLength = 0,
        closed: bool = false,

        /// Decomposition of the input scalar currently being distributed.
        scratch: [scratchLen(form)]Entry = undefined,
        scratch_len: u8 = 0,
        scratch_pos: u8 = 0,

        /// A starter that closed the run and has nowhere to go until the run
        /// has been drained. Keeping it here rather than past the run in
        /// `buffer` is what bounds occupancy at one run.
        held: Entry = undefined,
        has_held: bool = false,

        /// Consecutive non-starters, counted after decomposition and
        /// independently of the buffer, so composition cannot shrink a run
        /// past the limit and hide it.
        nonstarters: usize = 0,

        input_done: bool = false,
        failed: ?Error = null,

        /// The next scalar of the normalized text, or null at end of input.
        ///
        /// Once this returns an error the iterator stays failed and every
        /// later call returns the same one. Scalars already returned remain
        /// valid; a partially ordered over-limit run is never emitted.
        ///
        /// Normalization is inherently one combining run ahead of its output:
        /// a starter cannot be emitted until the following characters are
        /// known, since they may reorder before it (a decomposing form) or
        /// compose into it (a composing form). So a failure can preempt the
        /// run being accumulated, and `"ab\xff"` reports `InvalidUtf8` after
        /// yielding only `a`. What has been returned is always correct; it is
        /// not always everything that could in principle have been returned.
        pub fn next(self: *Self) Error!?u21 {
            if (self.failed) |failure| return failure;
            return self.step() catch |failure| {
                self.failed = failure;
                return failure;
            };
        }

        fn step(self: *Self) Error!?u21 {
            while (true) {
                if (self.closed) {
                    if (self.emitted < self.len) {
                        const entry = self.buffer[self.emitted];
                        self.emitted += 1;
                        return entry.scalar;
                    }
                    self.len = 0;
                    self.emitted = 0;
                    self.closed = false;
                    if (self.has_held) {
                        self.buffer[0] = self.held;
                        self.len = 1;
                        self.has_held = false;
                        self.nonstarters = 0;
                    } else if (self.input_done) {
                        return null;
                    }
                    continue;
                }

                const entry = (try self.pull()) orelse {
                    self.input_done = true;
                    self.finishRun();
                    self.closed = true;
                    if (self.len == 0) return null;
                    continue;
                };

                if (entry.ccc != 0) {
                    if (self.nonstarters == max_nonstarters) return error.SequenceTooLong;
                    self.nonstarters += 1;
                    self.buffer[self.len] = entry;
                    self.len += 1;
                    continue;
                }

                // A starter. It opens the run if none is open.
                if (self.len == 0) {
                    self.buffer[0] = entry;
                    self.len = 1;
                    self.nonstarters = 0;
                    continue;
                }

                // Otherwise it ends the run. Composition may still reach
                // across: Hangul L+V and LV+T are both starter pairs, and
                // several further pairs in Unicode 17 have a starter as their
                // second element, so a bare starter run stays open if it
                // composes.
                self.finishRun();
                if (compose and self.len == 1 and self.buffer[0].base and entry.composable) {
                    if (composePair(self.buffer[0].scalar, entry.scalar)) |composed| {
                        self.buffer[0].scalar = composed;
                        self.nonstarters = 0;
                        continue;
                    }
                }
                self.closed = true;
                self.held = entry;
                self.has_held = true;
            }
        }

        /// Canonically order the open run, and for a composing form compose it.
        ///
        /// Safe to call more than once on the same run: the sort is stable and
        /// idempotent, and a composing form only keeps a run open when
        /// composition reduced it to a bare starter, which resets the
        /// blocking context exactly as composing the whole run at once would.
        fn finishRun(self: *Self) void {
            canonicalOrder(self.buffer[0..self.len]);
            if (compose) self.len = composeRun(self.buffer[0..self.len]);
        }

        /// One fully decomposed scalar at a time, drawn from the input.
        fn pull(self: *Self) Error!?Entry {
            if (self.scratch_pos < self.scratch_len) {
                const entry = self.scratch[self.scratch_pos];
                self.scratch_pos += 1;
                return entry;
            }
            if (self.pos >= self.bytes.len) return null;
            const decoded = utf8.step(self.bytes[self.pos..]);
            // utf8.step recovers from bad input by consuming one byte. That is
            // right for the tolerant engines and wrong here, so the null
            // code point becomes an error instead of advancing.
            const cp = decoded.cp orelse return error.InvalidUtf8;
            self.pos += decoded.len;
            self.scratch_len = decomposeInto(&self.scratch, cp, compat);
            self.scratch_pos = 1;
            return self.scratch[0];
        }

        /// Encode the rest of this iterator's output into `buffer`, returning
        /// the written prefix.
        ///
        /// Takes the iterator by value, so a temporary can be chained and a
        /// stored one is left untouched. It resumes from the receiver's
        /// current position, which need not be the start of the input.
        ///
        /// On `NoSpace` no partial encoding is written, but bytes written
        /// before the failure remain. Retrying `NoSpace` needs a fresh
        /// iterator and more room; `SequenceTooLong` and `InvalidUtf8` are
        /// never fixed by a bigger buffer.
        pub fn writeTo(self: Self, buffer: []u8) WriteError![]u8 {
            var iterator = self;
            var written: usize = 0;
            while (try iterator.next()) |cp| {
                const needed = std.unicode.utf8CodepointSequenceLength(cp) catch unreachable;
                // Subtraction, never `written + needed > buffer.len`, so the
                // check cannot wrap in a build without runtime safety.
                if (buffer.len - written < needed) return error.NoSpace;
                written += std.unicode.utf8Encode(cp, buffer[written..]) catch unreachable;
            }
            return buffer[0..written];
        }
    };
}

/// Equivalence, decided in lockstep without materializing either form.
///
/// `.canonical` compares `NFD(a) == NFD(b)`; `.compatibility` compares
/// `NFKD(a) == NFKD(b)`. Each is form-independent within its own kind --
/// `NFD(a) == NFD(b)` exactly when `NFC(a) == NFC(b)`, and likewise for the
/// compatibility pair -- which is why the caller chooses an equivalence
/// relation and not a normalization form.
pub fn eql(a: []const u8, b: []const u8, comptime how: Equivalence) Error!bool {
    const form: Form = switch (how) {
        .canonical => .nfd,
        .compatibility => .nfkd,
    };
    var left = normalize(a, form);
    var right = normalize(b, form);
    while (true) {
        // Both operands are advanced before either result is examined, so a
        // malformed or over-long sequence in the second one is reported even
        // when the first has already run out.
        const one = try left.next();
        const other = try right.next();
        if (one == null or other == null) return one == null and other == null;
        if (one.? != other.?) return false;
    }
}

/// Whether `bytes` is already in `form`.
///
/// Short-circuits: a decisive `false` may leave the rest of the input
/// unexamined, so it is not a UTF-8 or sequence-length validator. A `true`
/// answer does mean the whole input was examined and accepted. Either result
/// gives way to `InvalidUtf8` or `SequenceTooLong` once encountered.
pub fn isNormalized(bytes: []const u8, comptime form: Form) Error!bool {
    const compat = comptime isCompat(form);
    const compose = comptime isCompose(form);
    var pos: usize = 0;
    var nonstarters: usize = 0;
    // Combining class of the previous character *as written*, which is what
    // the UAX #15 quick check compares.
    var written_previous_ccc: u8 = 0;
    // Highest combining class since the last *decomposed* starter. Keep
    // the maximum: later written marks may have lower classes than marks
    // hidden inside a precomposed character, without changing its NFC form.
    // A precomposed character contributes marks invisible in the input:
    // `U+00E9` is one written starter but decomposes to `e` and a class-230
    // mark.
    var decomposed_max_ccc: u8 = 0;
    // The last starter as written -- what a composition would attach to --
    // and where it begins, for the general fallback below.
    var starter: ?u21 = null;
    var starter_base = false;
    var region: usize = 0;

    while (pos < bytes.len) {
        const decoded = utf8.step(bytes[pos..]);
        const cp = decoded.cp orelse return error.InvalidUtf8;
        // One class lookup answers every question below.
        const class = properties.classOf(cp);
        const ccc = class.ccc;

        // Marks out of canonical order are normalized in no form, even when
        // each of them quick-checks as Yes on its own.
        if (ccc != 0 and written_previous_ccc > ccc) return false;

        if (compose) {
            // NFKC reads its own quick-check property, not NFC's: a code
            // point can quick-check Yes under NFC while quick-checking No
            // under NFKC, when its *canonical* decomposition target is
            // itself compatibility-decomposable (sixteen such code points in
            // Unicode 17.0.0; see the generator's `read_derived`).
            const qc = if (form == .nfkc) class.nfkc_quick_check else class.quick_check;
            switch (qc) {
                .no => return false,
                .yes => {},
                // Maybe means "composes with the character before it, for some
                // characters", and settling it is the expensive part of this
                // query.
                //
                // It cannot be settled locally in general. Decomposing can
                // reorder marks *inside* the run, which may enable a different
                // composition (`U+00E9 U+0323` is not NFC) or may recompose
                // right back to the input (`U+1E69 U+0323` is). Telling those
                // apart needs the real algorithm.
                //
                // But when nothing in the run outranks this character, no
                // reordering can happen, and the only question left is whether
                // it composes with the starter -- one lookup. That covers
                // ordinary accented text; the rest falls back. This reasoning
                // is unaffected by which composing form is in use: the Maybe
                // set is identical between NFC_QC and NFKC_QC, and a
                // character that is its own composition question is never
                // itself compatibility-decomposable (a compatibility-mapped
                // code point's own NFKC_QC is always No, never Maybe).
                // A Maybe with its own canonical decomposition can compose
                // through that decomposition even when the written pair has
                // no mapping (for example U+1611E U+16123). Settle it fully.
                .maybe => if (starter != null and !class.decomposes and decomposed_max_ccc <= ccc) {
                    // UAX #15 blocking: `cp` is blocked from the starter when
                    // something between them has a class at least as large.
                    // Only marks retained after the written starter block it.
                    // Marks inside its decomposition are already absorbed:
                    // the diaeresis in ü does not block ü + acute -> ǘ.
                    // Decomposed context above still guards against reordering.
                    const blocked = written_previous_ccc != 0 and written_previous_ccc >= ccc;
                    if (!blocked and starter_base and class.composable and
                        composePair(starter.?, cp) != null) return false;
                } else {
                    if (!try settled(bytes[region..], pos - region + decoded.len, form)) return false;
                },
            }
        } else {
            // .nfd or .nfkd. NFKD_QC is No exactly when the code point
            // decomposes canonically, compatibly, or (added by the engine,
            // absent from the table) as Hangul; `classOf` already covers
            // Hangul as part of `decomposes`.
            if (class.decomposes or (compat and class.compat_decomposes)) return false;
        }

        // Fold the decomposed form in. The run limit and the decomposed
        // context above are both properties of the decomposed text -- but for
        // a character that does not decompose under this form, it *is* the
        // decomposed text, so the common path needs no second lookup and no
        // scratch buffer.
        const decomposes_here = class.decomposes or (compat and class.compat_decomposes);
        if (!decomposes_here) {
            if (ccc == 0) {
                nonstarters = 0;
                decomposed_max_ccc = 0;
            } else {
                if (nonstarters == max_nonstarters) return error.SequenceTooLong;
                nonstarters += 1;
                decomposed_max_ccc = @max(decomposed_max_ccc, ccc);
            }
        } else {
            var scratch: [scratchLen(form)]Entry = undefined;
            const len = decomposeInto(&scratch, cp, compat);
            for (scratch[0..len]) |entry| {
                if (entry.ccc == 0) {
                    nonstarters = 0;
                    decomposed_max_ccc = 0;
                    continue;
                }
                if (nonstarters == max_nonstarters) return error.SequenceTooLong;
                nonstarters += 1;
                decomposed_max_ccc = @max(decomposed_max_ccc, entry.ccc);
            }
        }

        if (ccc == 0) {
            starter = cp;
            starter_base = class.composition_base;
            region = pos;
        }
        written_previous_ccc = ccc;
        pos += decoded.len;
    }
    return true;
}

/// Whether normalizing `region` to `form` leaves its first `prefix_len` bytes
/// unchanged. The general way to settle a Maybe, used when the fast path
/// above cannot rule out a reordering inside the run. `form` is always a
/// composing form here (`.nfc` or `.nfkc`): only `isNormalized`'s composing
/// branch calls this.
fn settled(region: []const u8, prefix_len: usize, comptime form: Form) Error!bool {
    var iterator = normalize(region[0..prefix_len], form);
    var pos: usize = 0;
    while (try iterator.next()) |cp| {
        var encoded: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(cp, &encoded) catch unreachable;
        if (pos + len > prefix_len) return false;
        if (!std.mem.eql(u8, region[pos..][0..len], encoded[0..len])) return false;
        pos += len;
    }
    return pos == prefix_len;
}

/// The UAX #15 quick check, three-valued and without settling anything.
///
/// `Maybe` means the answer depends on characters this scan deliberately does
/// not examine. `isNormalized` settles it and returns a boolean; this is the
/// cheap question underneath, useful when a caller wants to skip work on a
/// definite Yes and is content to do its own thing on Maybe.
///
/// Contract, chosen to be simple rather than clever:
///
/// - The whole slice is scanned, even after a decisive `No`, so malformed
///   UTF-8 anywhere is reported. `isNormalized` may instead stop at a
///   decisive `false` and leave a suffix unread.
/// - State is one combining class. The configured run limit is **not**
///   enforced, so a `Yes` here does not promise that the bounded normalizer
///   will accept the input: a run longer than `max_nonstarters` is perfectly
///   normalized and still `SequenceTooLong` to normalize.
/// - Empty input is `Yes`.
/// - `No` overrides `Maybe`, and `Maybe` overrides `Yes`.
///
/// A decomposing form is two-valued here: a decomposition under that form,
/// Hangul included, is a definite `No`, and nothing about it is conditional
/// on later context.
pub fn isNormalizedQuick(bytes: []const u8, comptime form: Form) error{InvalidUtf8}!QuickCheck {
    const compat = comptime isCompat(form);
    const compose = comptime isCompose(form);
    var pos: usize = 0;
    var previous_ccc: u8 = 0;
    var result: QuickCheck = .yes;
    while (pos < bytes.len) {
        const decoded = utf8.step(bytes[pos..]);
        const cp = decoded.cp orelse return error.InvalidUtf8;
        const class = properties.classOf(cp);

        // Marks out of canonical order are normalized in no form.
        if (class.ccc != 0 and previous_ccc > class.ccc) {
            result = .no;
        } else if (compose) {
            const qc = if (form == .nfkc) class.nfkc_quick_check else class.quick_check;
            switch (qc) {
                .no => result = .no,
                .maybe => if (result == .yes) {
                    result = .maybe;
                },
                .yes => {},
            }
        } else if (class.decomposes or (compat and class.compat_decomposes)) {
            result = .no;
        }
        previous_ccc = class.ccc;
        pos += decoded.len;
    }
    return result;
}
