//! Default UAX #29 word boundaries.
//!
//! Rules and property values are pinned to Unicode 17.0.0 and
//! [UAX #29 revision 47](https://www.unicode.org/reports/tr29/tr29-47.html#Word_Boundary_Rules).
//! These are the *default*, locale-independent boundaries: they do not perform
//! dictionary segmentation, so they do not find words in Thai, Lao, Khmer,
//! Myanmar, Chinese or Japanese text.
//!
//! The segmentation partitions the input. Punctuation and whitespace are
//! emitted as their own spans, flagged `is_word = false`.
const std = @import("std");
const utf8 = @import("encoding").utf8;
const ascii_scan = @import("encoding").ascii;
const word_properties = @import("tables").word;
const ascii = @import("word_ascii.zig");

pub const WordBreak = word_properties.WordBreak;

pub const Span = struct {
    start: usize,
    end: usize,
    /// True when at least one scalar in the span is `Alphabetic` or has a
    /// numeric general category. zunic's convenience, not a UAX #29 rule.
    is_word: bool,
};

/// One scalar, carrying exactly the three facts the rules and the flag need.
pub const Token = struct {
    len: usize,
    wb: WordBreak,
    word_like: bool,
    extended_pictographic: bool,
};

/// Malformed input consumes one byte and is classified `WB=Other`, with
/// neither the pictographic nor the word-like bit. The boundary rules then
/// apply to it unchanged, so a following `Extend` still attaches by WB4.
pub const malformed: Token = .{
    .len = 1,
    .wb = .other,
    .word_like = false,
    .extended_pictographic = false,
};

pub inline fn classify(bytes: []const u8, start: usize) Token {
    const decoded = utf8.step(bytes[start..]);
    const cp = decoded.cp orelse return malformed;
    const props = word_properties.wordProperties(cp);
    return .{
        .len = decoded.len,
        .wb = props.wb,
        .word_like = props.word_like,
        .extended_pictographic = props.extended_pictographic,
    };
}

inline fn isAHLetter(wb: WordBreak) bool {
    return wb == .aletter or wb == .hebrew_letter;
}

/// `MidNumLetQ` in the rule definitions.
inline fn isMidNumLetQ(wb: WordBreak) bool {
    return wb == .midnumlet or wb == .single_quote;
}

/// The characters WB4 folds into the preceding one.
pub inline fn isIgnorable(wb: WordBreak) bool {
    return wb == .extend or wb == .format or wb == .zwj;
}

inline fn isNewlineLike(wb: WordBreak) bool {
    return wb == .newline or wb == .cr or wb == .lf;
}

/// Whether WB4 folds `cur` into the preceding character. Only meaningful when
/// a preceding character exists: at start of text WB1 has already broken, so
/// an ignorable there is a character in its own right. WB3a has broken after
/// CR, LF and Newline for the same reason.
pub inline fn absorbs(raw_prev: WordBreak, cur: WordBreak) bool {
    return isIgnorable(cur) and !isNewlineLike(raw_prev);
}

/// Left context for a boundary decision, describing the text up to and
/// including the character before the gap.
///
/// `raw_prev` is the immediately preceding character, used by WB3 through
/// WB3d, which look at raw adjacency. `sig` and `sig_prev` are the last two
/// characters that WB4 did *not* fold away, used by WB5 onwards. Keeping both
/// is what lets `<ZWJ>` join an emoji while an intervening `Format` does not.
pub const State = struct {
    raw_prev: WordBreak,
    sig: WordBreak,
    sig_prev: WordBreak,
    /// Whether an odd number of Regional_Indicators immediately precedes the
    /// gap, which is the whole of WB15 and WB16.
    ri_odd: bool,

    pub inline fn init(first: WordBreak) State {
        return .{
            .raw_prev = first,
            .sig = first,
            .sig_prev = .other,
            .ri_odd = first == .regional_indicator,
        };
    }

    /// Fold one character into the context. `absorbed` is `absorbs()` for the
    /// gap this character was just decided at.
    pub inline fn advance(self: *State, cur: WordBreak, absorbed: bool) void {
        self.raw_prev = cur;
        if (absorbed) return;
        self.sig_prev = self.sig;
        self.sig = cur;
        self.ri_odd = cur == .regional_indicator and !self.ri_odd;
    }
};

/// Which character the WB6, WB7b and WB12 lookahead has to find for its rule
/// to fire. At most one of the three can apply at any gap: they disagree on
/// `cur` or on `sig`, so a decision never carries more than one request.
pub const Lookahead = enum(u2) { none, ah_letter, hebrew_letter, numeric };

/// The outcome of the folded-context rules, WB5 through WB999.
pub const Late = packed struct(u8) {
    /// The decision when no lookahead is requested, or when it fails. All
    /// three lookahead rules join on success, so success always means "keep".
    brk: bool,
    lookahead: Lookahead = .none,
    _padding: u5 = 0,
};

/// WB3 through WB4: the rules that read raw adjacency, before WB4 folds
/// anything away. Returns null when they leave the decision to WB5 onwards.
///
/// These need `cur.extended_pictographic`, which no later rule reads.
pub inline fn earlyDecision(raw_prev: WordBreak, cur: Token) ?bool {
    // WB3: CR x LF
    if (raw_prev == .cr and cur.wb == .lf) return false;
    // WB3a: (Newline | CR | LF) div
    if (isNewlineLike(raw_prev)) return true;
    // WB3b: div (Newline | CR | LF)
    if (isNewlineLike(cur.wb)) return true;
    // WB3c: ZWJ x \p{Extended_Pictographic}
    if (raw_prev == .zwj and cur.extended_pictographic) return false;
    // WB3d: WSegSpace x WSegSpace
    if (raw_prev == .wsegspace and cur.wb == .wsegspace) return false;
    // WB4: X (Extend | Format | ZWJ)* -> X. WB3a already returned for the
    // start-of-text and newline exceptions, so reaching here means it applies.
    if (isIgnorable(cur.wb)) return false;
    return null;
}

/// WB5 through WB999, in specification order: the single definition of the
/// folded-context rules.
///
/// Only reachable when `earlyDecision` deferred, so `cur` is never ignorable
/// or newline-like and `sig`/`sig_prev` are the last two characters WB4 did
/// not fold away. `machine` evaluates this at comptime for every state and
/// character, so on the hot path it is a table read; it stays the definition
/// both engines are checked against.
pub fn lateDecision(sig: WordBreak, sig_prev: WordBreak, ri_odd: bool, cur: WordBreak) Late {
    const ah_prev = isAHLetter(sig);
    const ah_cur = isAHLetter(cur);
    var lookahead: Lookahead = .none;

    // WB5: AHLetter x AHLetter
    if (ah_prev and ah_cur) return .{ .brk = false };
    // WB6: AHLetter x (MidLetter | MidNumLetQ) AHLetter
    if (ah_prev and (cur == .midletter or isMidNumLetQ(cur))) lookahead = .ah_letter;
    // WB7: AHLetter (MidLetter | MidNumLetQ) x AHLetter
    if (ah_cur and isAHLetter(sig_prev) and
        (sig == .midletter or isMidNumLetQ(sig))) return .{ .brk = false, .lookahead = lookahead };
    // WB7a: Hebrew_Letter x Single_Quote
    if (sig == .hebrew_letter and cur == .single_quote) return .{ .brk = false, .lookahead = lookahead };
    // WB7b: Hebrew_Letter x Double_Quote Hebrew_Letter
    if (sig == .hebrew_letter and cur == .double_quote) lookahead = .hebrew_letter;
    // WB7c: Hebrew_Letter Double_Quote x Hebrew_Letter
    if (cur == .hebrew_letter and sig == .double_quote and
        sig_prev == .hebrew_letter) return .{ .brk = false, .lookahead = lookahead };
    // WB8: Numeric x Numeric
    if (sig == .numeric and cur == .numeric) return .{ .brk = false, .lookahead = lookahead };
    // WB9: AHLetter x Numeric
    if (ah_prev and cur == .numeric) return .{ .brk = false, .lookahead = lookahead };
    // WB10: Numeric x AHLetter
    if (sig == .numeric and ah_cur) return .{ .brk = false, .lookahead = lookahead };
    // WB11: Numeric (MidNum | MidNumLetQ) x Numeric
    if (cur == .numeric and sig_prev == .numeric and
        (sig == .midnum or isMidNumLetQ(sig))) return .{ .brk = false, .lookahead = lookahead };
    // WB12: Numeric x (MidNum | MidNumLetQ) Numeric
    if (sig == .numeric and (cur == .midnum or isMidNumLetQ(cur))) lookahead = .numeric;
    // WB13: Katakana x Katakana
    if (sig == .katakana and cur == .katakana) return .{ .brk = false, .lookahead = lookahead };
    // WB13a: (AHLetter | Numeric | Katakana | ExtendNumLet) x ExtendNumLet
    if (cur == .extendnumlet and
        (ah_prev or sig == .numeric or sig == .katakana or
            sig == .extendnumlet)) return .{ .brk = false, .lookahead = lookahead };
    // WB13b: ExtendNumLet x (AHLetter | Numeric | Katakana)
    if (sig == .extendnumlet and
        (ah_cur or cur == .numeric or cur == .katakana)) return .{ .brk = false, .lookahead = lookahead };
    // WB15/WB16: (RI RI)* RI x RI
    if (sig == .regional_indicator and cur == .regional_indicator and
        ri_odd) return .{ .brk = false, .lookahead = lookahead };
    // WB999: Any div Any
    return .{ .brk = true, .lookahead = lookahead };
}

/// Apply a decision, asking for the next unfolded character only if a rule
/// wants one.
///
/// `following` is `anytype` so the tabled and reference iterators can each
/// pass their own lookahead without a shared vtable. The contract it must
/// satisfy is one method:
///
///     fn significant(self) ?WordBreak
///
/// returning the next character that the folding rules do not ignore, or
/// null at end of text. Getting that wrong surfaces as an error inside this
/// function rather than at the call, so it is written down here.
inline fn resolve(late: Late, following: anytype) bool {
    if (late.lookahead != .none) {
        if (following.significant()) |next| {
            const satisfied = switch (late.lookahead) {
                .none => unreachable,
                .ah_letter => isAHLetter(next),
                .hebrew_letter => next == .hebrew_letter,
                .numeric => next == .numeric,
            };
            if (satisfied) return false;
        }
    }
    return late.brk;
}

/// `lateDecision`, evaluated at comptime for every state and character.
///
/// The state update needs no table: `sig_prev` becomes `sig`, `sig` becomes
/// the character just folded in, and the RI parity toggles. Only the decision
/// is compiled, and rows that decide identically are stored once, which is
/// what collapses the 722 raw states. The saving is derived, not asserted:
/// nothing here names which distinctions the rules happen to ignore.
pub const machine = struct {
    pub const class_count = @typeInfo(WordBreak).@"enum".fields.len;
    pub const state_count = class_count * class_count * 2;

    pub inline fn stateIndex(sig: WordBreak, sig_prev: WordBreak, ri_odd: bool) usize {
        return ((@as(usize, @intFromEnum(sig)) * class_count) +
            @intFromEnum(sig_prev)) * 2 + @intFromBool(ri_odd);
    }

    const built = blk: {
        @setEvalBranchQuota(1_000_000);
        var rows: [state_count][class_count]u8 = undefined;
        var index_of: [state_count]u8 = undefined;
        var distinct: usize = 0;
        for (0..class_count) |sig| {
            for (0..class_count) |sig_prev| {
                for (0..2) |parity| {
                    var row: [class_count]u8 = undefined;
                    for (0..class_count) |cur| {
                        const late = lateDecision(
                            @enumFromInt(sig),
                            @enumFromInt(sig_prev),
                            parity == 1,
                            @enumFromInt(cur),
                        );
                        row[cur] = @bitCast(late);
                    }
                    const index = stateIndex(@enumFromInt(sig), @enumFromInt(sig_prev), parity == 1);
                    var found: ?usize = null;
                    for (rows[0..distinct], 0..) |existing, i| {
                        if (std.mem.eql(u8, &existing, &row)) {
                            found = i;
                            break;
                        }
                    }
                    if (found) |i| {
                        index_of[index] = @intCast(i);
                    } else {
                        if (distinct > 255) @compileError("word decision rows no longer fit a u8 index");
                        rows[distinct] = row;
                        index_of[index] = @intCast(distinct);
                        distinct += 1;
                    }
                }
            }
        }
        var flat: [state_count * class_count]u8 = undefined;
        for (0..distinct) |i| @memcpy(flat[i * class_count ..][0..class_count], &rows[i]);
        break :blk .{ .row_of = index_of, .rows = distinct, .data = flat };
    };

    pub const row_count = built.rows;
    pub const row_of = built.row_of;
    pub const decisions = built.data[0 .. row_count * class_count].*;

    /// Row index plus decision table. The state update is arithmetic, so
    /// there is no transition table to count here.
    pub const data_bytes = row_of.len + decisions.len;

    comptime {
        if (data_bytes > 8 * 1024) @compileError("word machine exceeds its 8 KiB budget");
    }

    pub inline fn decide(sig: WordBreak, sig_prev: WordBreak, ri_odd: bool, cur: WordBreak) Late {
        const row = row_of[stateIndex(sig, sig_prev, ri_odd)];
        return @bitCast(decisions[@as(usize, row) * class_count + @intFromEnum(cur)]);
    }
};

/// The rules, composed. `tabled` selects the compiled decision table over
/// direct evaluation; both read the same `lateDecision`.
/// `following` carries the same one-method contract `resolve` documents.
pub fn breakBefore(comptime tabled: bool, state: State, cur: Token, following: anytype) bool {
    if (earlyDecision(state.raw_prev, cur)) |decided| return decided;
    const late = if (tabled)
        machine.decide(state.sig, state.sig_prev, state.ri_odd, cur.wb)
    else
        lateDecision(state.sig, state.sig_prev, state.ri_odd, cur.wb);
    return resolve(late, following);
}

/// Scans forward for the next character WB4 does not fold away.
///
/// The characters it skips are exactly the ignorable run that follows `cur`,
/// and `cur` is always a punctuation candidate, so it is never CR, LF or
/// Newline and the run always folds. Each such run belongs to one character,
/// so at most one lookahead ever crosses it: a complete traversal decodes
/// fewer than two scalars per input scalar.
fn Following(comptime instrumented: bool) type {
    return struct {
        bytes: []const u8,
        from: usize,
        counters: if (instrumented) *Counters else void,

        fn significant(self: @This()) ?WordBreak {
            var pos = self.from;
            while (pos < self.bytes.len) {
                const token = classify(self.bytes, pos);
                if (instrumented) self.counters.lookahead_scalars += 1;
                if (!isIgnorable(token.wb)) return token.wb;
                pos += token.len;
            }
            return null;
        }
    };
}

pub const Counters = struct {
    scalars: usize = 0,
    lookahead_scalars: usize = 0,
};

pub const Iterator = IteratorImpl(true, false);
pub const ReferenceIterator = IteratorImpl(false, false);
pub const InstrumentedIterator = IteratorImpl(true, true);

pub fn iterator(bytes: []const u8) Iterator {
    return Iterator.init(bytes);
}

/// The rules evaluated directly, with no compiled table. Kept for the
/// differential test and for the table's benchmark peer.
pub fn referenceIterator(bytes: []const u8) ReferenceIterator {
    return ReferenceIterator.init(bytes);
}

/// Test-only: `iterator` with decoded-scalar counters enabled.
pub fn instrumentedIterator(bytes: []const u8) InstrumentedIterator {
    return InstrumentedIterator.init(bytes);
}

fn IteratorImpl(comptime tabled: bool, comptime instrumented: bool) type {
    return struct {
        const Self = @This();

        bytes: []const u8,
        /// First byte of the span the next call will emit.
        start: usize,
        /// First byte of the character already classified into `cur`.
        cur_start: usize,
        /// First byte not yet classified.
        scan: usize,
        cur: Token,
        state: State,
        exhausted: bool,
        ascii_mode: enum { unknown, unicode, ascii } = .unknown,
        counters: if (instrumented) Counters else void = if (instrumented) .{} else {},

        fn init(bytes: []const u8) Self {
            var self: Self = .{
                .bytes = bytes,
                .start = 0,
                .cur_start = 0,
                .scan = 0,
                .cur = malformed,
                .state = State.init(.other),
                .exhausted = bytes.len == 0,
            };
            if (bytes.len == 0) return self;
            // WB1 puts a boundary before the first character, so it is always
            // significant: an ignorable here has nothing to fold into.
            self.cur = classify(bytes, 0);
            if (instrumented) self.counters.scalars += 1;
            self.scan = self.cur.len;
            self.state = State.init(self.cur.wb);
            return self;
        }

        pub fn next(self: *Self) ?Span {
            if (self.exhausted) return null;
            // Decide once, on first traversal rather than when opening the view.
            // Mixed text stays with the full rules: marks can attach to ASCII,
            // and punctuation lookahead can reach beyond an ASCII run.
            if (tabled and self.ascii_mode != .unicode) {
                if (self.ascii_mode == .unknown) {
                    self.ascii_mode = if (ascii_scan.isAscii(self.bytes)) .ascii else .unicode;
                }
                if (self.ascii_mode == .ascii) {
                    const start = self.start;
                    const end = ascii.next(self.bytes, start);
                    self.start = end.offset;
                    self.exhausted = end.offset == self.bytes.len;
                    if (instrumented) self.counters.scalars = end.offset;
                    return .{ .start = start, .end = end.offset, .is_word = end.is_word };
                }
            }
            const start = self.start;
            var is_word = self.cur.word_like;
            while (true) {
                const gap = self.scan;
                if (gap >= self.bytes.len) {
                    self.exhausted = true;
                    // WB2 puts a boundary at end of text.
                    return .{ .start = start, .end = self.bytes.len, .is_word = is_word };
                }
                const cur = classify(self.bytes, gap);
                if (instrumented) self.counters.scalars += 1;
                const following: Following(instrumented) = .{
                    .bytes = self.bytes,
                    .from = gap + cur.len,
                    .counters = if (instrumented) &self.counters else {},
                };
                const boundary = breakBefore(tabled, self.state, cur, following);

                self.state.advance(cur.wb, absorbs(self.state.raw_prev, cur.wb));
                self.cur = cur;
                self.cur_start = gap;
                self.scan = gap + cur.len;

                if (boundary) {
                    self.start = gap;
                    return .{ .start = start, .end = gap, .is_word = is_word };
                }
                is_word = is_word or cur.word_like;
            }
        }
    };
}
