//! Canonical normalization: Unicode 16.0 Forms C and D (UAX #15).
//!
//! Compatibility forms are deliberately absent. `Form` has no `nfkc`/`nfkd`
//! and `Equivalence` has no `.compatibility`, so a caller cannot accidentally
//! ask for a guarantee this module does not provide: `U+FB01` and `"fi"` are
//! compatibility-equivalent but **not** canonically equivalent, and answering
//! otherwise gives silently wrong results in search and deduplication.
//!
//! Nothing here allocates. The working buffer is inline and its size is a
//! compile-time module setting, `-Dnormalization-buffer-bytes`, so a combining
//! sequence longer than the configured limit is rejected with
//! `error.SequenceTooLong` rather than truncated, silently reordered, or
//! quietly declared equal to something else.
//!
//! Unlike the rest of the package, normalization is **strict about malformed
//! UTF-8**: an invalid encoding is `error.InvalidUtf8`, never a replacement
//! character and never a skipped byte. Two different invalid inputs must not
//! be able to compare equal by both decaying to U+FFFD. Grapheme, word,
//! width, wrapping and `utf8.step` keep their tolerant behaviour.
const std = @import("std");
const build_options = @import("build_options");
const utf8 = @import("utf8.zig");
const properties = @import("normalization_properties.zig");

pub const Form = enum { nfc, nfd };
pub const Equivalence = enum { canonical };

pub const Error = error{ InvalidUtf8, SequenceTooLong };
pub const WriteError = Error || error{NoSpace};

/// Working buffer for one iterator, in bytes. See `-Dnormalization-buffer-bytes`.
pub const buffer_bytes: usize = build_options.normalization_buffer_bytes;
pub const buffer_entries: usize = buffer_bytes / @sizeOf(Entry);
/// The longest run of non-starters this build accepts, counted after full
/// canonical decomposition. Two entries are headroom: the starter that opens
/// the run, and one spare.
pub const max_nonstarters: usize = buffer_entries - 2;
// Include the length as well as every index, at any supported buffer size.
const RunLength = std.math.IntFittingRange(0, buffer_entries);

comptime {
    if (buffer_bytes == 0 or buffer_bytes % 32 != 0)
        @compileError("normalization-buffer-bytes must be a positive multiple of 32");
    if (@sizeOf(Entry) != 4) @compileError("Entry must be four bytes");
}

/// One decomposed scalar and its combining class.
const Entry = packed struct(u32) {
    scalar: u21,
    ccc: u8,
    _padding: u3 = 0,
};

// UAX #15 section 16. These are the only mappings zunic computes rather than
// stores; the generated tables deliberately contain no Hangul.
const s_base = 0xAC00;
const l_base = 0x1100;
const v_base = 0x1161;
const t_base = 0x11A7;
const l_count = 19;
const v_count = 21;
const t_count = 28;
const n_count = v_count * t_count;
const s_count = l_count * n_count;

/// Full canonical decomposition of one scalar, into at most four entries.
///
/// Four is the measured maximum over the pinned data and is checked by
/// `test-normalization-properties.py`, so the recursion below cannot overrun
/// a caller's four-entry array.
fn decomposeInto(out: []Entry, cp: u21) u8 {
    if (cp >= s_base and cp < s_base + s_count) {
        const index = cp - s_base;
        out[0] = entryOf(@intCast(l_base + index / n_count));
        out[1] = entryOf(@intCast(v_base + (index % n_count) / t_count));
        if (index % t_count == 0) return 2;
        out[2] = entryOf(@intCast(t_base + index % t_count));
        return 3;
    }
    const mapping = properties.decomposition(cp) orelse {
        out[0] = entryOf(cp);
        return 1;
    };
    var len: u8 = 0;
    for (mapping.scalars) |scalar| len += decomposeInto(out[len..], @intCast(scalar));
    return len;
}

fn entryOf(cp: u21) Entry {
    return .{ .scalar = cp, .ccc = properties.combiningClass(cp) };
}

/// The primary composite of two scalars, Hangul included.
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
        if (last_ccc < @as(i16, current.ccc)) {
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

/// An upper bound on the UTF-8 length of either canonical form of `input_len`
/// bytes. The factor is derived from the pinned data during generation.
///
/// This depends only on a byte count, so it cannot detect malformed UTF-8 or
/// an over-long combining sequence: a buffer of this size rules out
/// `error.NoSpace` and nothing else.
pub fn normalizedLenBound(input_len: usize, comptime form: Form) error{Overflow}!usize {
    // Both forms reach 3x growth. NFC decomposes the excluded U+1D160 into
    // three supplementary musical symbols: four UTF-8 bytes become twelve.
    _ = form;
    return std.math.mul(usize, input_len, properties.expansion_factor);
}

pub fn Iterator(comptime form: Form) type {
    return struct {
        const Self = @This();

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
        scratch: [4]Entry = undefined,
        scratch_len: u8 = 0,
        scratch_pos: u8 = 0,

        /// A starter that closed the run and has nowhere to go until the run
        /// has been drained. Keeping it here rather than past the run in
        /// `buffer` is what bounds occupancy at one run.
        held: Entry = undefined,
        has_held: bool = false,

        /// Consecutive non-starters, counted after decomposition and
        /// independently of the buffer, so NFC composition cannot shrink a run
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
        /// known, since they may reorder before it (NFD) or compose into it
        /// (NFC). So a failure can preempt the run being accumulated, and
        /// `"ab\xff"` reports `InvalidUtf8` after yielding only `a`. What has
        /// been returned is always correct; it is not always everything that
        /// could in principle have been returned.
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
                // across: Hangul L+V and LV+T are both starter pairs, and 59
                // further pairs in Unicode 16 have a starter as their second
                // element, so a bare starter run stays open if it composes.
                self.finishRun();
                if (form == .nfc and self.len == 1) {
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

        /// Canonically order the open run, and for NFC compose it.
        ///
        /// Safe to call more than once on the same run: the sort is stable and
        /// idempotent, and NFC only keeps a run open when composition reduced
        /// it to a bare starter, which resets the blocking context exactly as
        /// composing the whole run at once would.
        fn finishRun(self: *Self) void {
            canonicalOrder(self.buffer[0..self.len]);
            if (form == .nfc) self.len = composeRun(self.buffer[0..self.len]);
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
            self.scratch_len = decomposeInto(&self.scratch, cp);
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

/// Canonical equivalence: `NFD(a) == NFD(b)`, decided in lockstep without
/// materializing either form.
///
/// Form-independent, since `NFD(a) == NFD(b)` exactly when
/// `NFC(a) == NFC(b)`, which is why the caller chooses an equivalence
/// relation and not a normalization form.
pub fn eql(a: []const u8, b: []const u8, comptime how: Equivalence) Error!bool {
    comptime std.debug.assert(how == .canonical);
    var left = normalize(a, .nfd);
    var right = normalize(b, .nfd);
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
    var pos: usize = 0;
    var last_ccc: u8 = 0;
    var nonstarters: usize = 0;
    // Start of the region a Maybe would have to be settled over: the last
    // position at which output could not depend on anything earlier.
    var region: usize = 0;
    while (pos < bytes.len) {
        const decoded = utf8.step(bytes[pos..]);
        const cp = decoded.cp orelse return error.InvalidUtf8;

        const ccc = properties.combiningClass(cp);
        // Count the decomposed text even for starters: a precomposed starter
        // can contribute trailing non-starters to the following run.
        var scratch: [4]Entry = undefined;
        const len = decomposeInto(&scratch, cp);
        for (scratch[0..len]) |entry| {
            if (entry.ccc == 0) {
                nonstarters = 0;
            } else {
                if (nonstarters == max_nonstarters) return error.SequenceTooLong;
                nonstarters += 1;
            }
        }
        // Marks out of canonical order are not normalized in either form, even
        // when every one of them individually quick-checks as Yes.
        if (last_ccc > ccc and ccc != 0) return false;
        last_ccc = ccc;

        switch (form) {
            .nfd => {
                if (cp >= s_base and cp < s_base + s_count) return false;
                if (!properties.nfdQuickCheckIsYes(cp)) return false;
            },
            .nfc => switch (properties.nfcQuickCheck(cp)) {
                .no => return false,
                .yes => {},
                // Maybe means "composes with something before it, sometimes".
                // Settle it over the region this scalar can reach back into,
                // which starts at the last starter that could still compose.
                .maybe => if (!try settled(bytes[region..], pos - region + decoded.len)) return false,
            },
        }
        if (ccc == 0) region = pos;
        pos += decoded.len;
    }
    return true;
}

/// Whether normalizing `region` to NFC leaves its first `prefix_len` bytes
/// unchanged. Used only to settle a `Maybe`, over a region that starts at a
/// starter and is bounded by the configured run limit.
fn settled(region: []const u8, prefix_len: usize) Error!bool {
    var iterator = normalize(region[0..prefix_len], .nfc);
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
