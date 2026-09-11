//! Decoded Unicode scalar facts for consumers that need to compose rules.
//!
//! Invalid UTF-8 consumes one byte and has `codepoint == null`; its Unicode
//! properties use the package's existing malformed-input fallbacks.
const properties = @import("tables").properties;
const utf8 = @import("utf8.zig");

pub const Token = struct {
    start: usize,
    end: usize,
    codepoint: ?u21,
    grapheme: properties.GraphemeProperties,
    line_break: properties.LineBreak,
    cell_width: u2,
    east_asian_wide: bool,
};

/// Internal token used by composed scans that also need line-break predicates.
/// Keep the public Token unchanged for consumers constructing scalar facts.
pub const ClassifiedToken = struct {
    start: usize,
    end: usize,
    codepoint: ?u21,
    record: properties.Record,

    pub inline fn scalarToken(self: ClassifiedToken) Token {
        return .{
            .start = self.start,
            .end = self.end,
            .codepoint = self.codepoint,
            .grapheme = properties.graphemeOf(self.record),
            .line_break = self.record.line_break,
            .cell_width = self.record.width,
            .east_asian_wide = self.record.east_asian_wide,
        };
    }
};

/// Compact token for consumers that need line-break facts but not a public
/// scalar token or grapheme classification.
pub const LineBreakToken = struct {
    end: usize,
    record: properties.Record,
};

pub fn lineBreakAt(bytes: []const u8, start: usize) LineBreakToken {
    if (start < bytes.len and bytes[start] < 0x80) {
        const base = comptime @as(usize, properties.record_index[0]) << properties.record_block_shift;
        return .{ .end = start + 1, .record = @bitCast(properties.record_data[base + bytes[start]]) };
    }
    const decoded = utf8.step(bytes[start..]);
    return .{
        .end = start + decoded.len,
        .record = if (decoded.cp) |cp| properties.record(cp) else malformedRecord(),
    };
}

/// The scanner and LB25 lookahead share this decoder, including its optional
/// counters. Every valid decode performs exactly one fused property lookup.
pub fn Classifier(comptime instrumented: bool) type {
    return struct {
        decoded_scalars: if (instrumented) usize else void = if (instrumented) 0 else {},
        property_lookups: if (instrumented) usize else void = if (instrumented) 0 else {},

        pub fn at(self: *@This(), bytes: []const u8, start: usize) ClassifiedToken {
            if (start < bytes.len and bytes[start] < 0x80) {
                if (instrumented) {
                    self.decoded_scalars += 1;
                    self.property_lookups += 1;
                }
                const base = comptime @as(usize, properties.record_index[0]) << properties.record_block_shift;
                const r: properties.Record = @bitCast(properties.record_data[base + bytes[start]]);
                return .{ .start = start, .end = start + 1, .codepoint = bytes[start], .record = r };
            }
            const step = utf8.step(bytes[start..]);
            if (instrumented and step.len != 0) self.decoded_scalars += 1;
            if (step.cp) |cp| {
                if (instrumented) self.property_lookups += 1;
                const r = properties.record(cp);
                return .{ .start = start, .end = start + step.len, .codepoint = cp, .record = r };
            }
            // Predicates historically use cp=0 for malformed bytes and EOT.
            // Its AL-like raw class still comes from the tolerant token.
            return .{
                .start = start,
                .end = start + step.len,
                .codepoint = null,
                .record = malformedRecord(),
            };
        }
    };
}

/// What a malformed byte looks like, stated once. Every field the token
/// contract mentions is set here rather than inherited from `record(0)`: two
/// of them used to arrive that way, so NUL's properties were silently part of
/// the definition and a table regeneration could have moved them.
inline fn malformedRecord() properties.Record {
    return comptime blk: {
        var r = properties.record(0);
        r.gcb = .other;
        r.incb = .none;
        r.extended_pictographic = false;
        r.line_break = .al;
        r.width = 0;
        r.line_break_category = properties.line_break_malformed_category;
        r.east_asian_wide = false;
        break :blk r;
    };
}

/// The same facts as a public `Token`. `at` used to spell them out a second
/// time; the two agreed only by inspection, and nothing made them stay that
/// way.
inline fn malformedToken(start: usize, end: usize) Token {
    const r = comptime malformedRecord();
    return .{
        .start = start,
        .end = end,
        .codepoint = null,
        .grapheme = properties.graphemeOf(r),
        .line_break = r.line_break,
        .cell_width = r.width,
        .east_asian_wide = r.east_asian_wide,
    };
}

pub const Iterator = struct {
    bytes: []const u8,
    offset: usize = 0,

    pub fn next(self: *Iterator) ?Token {
        if (self.offset == self.bytes.len) return null;
        const start = self.offset;
        const token = at(self.bytes, start);
        self.offset = token.end;
        return token;
    }
};

pub fn iterator(bytes: []const u8) Iterator {
    return .{ .bytes = bytes };
}

pub fn at(bytes: []const u8, start: usize) Token {
    // One record carries the grapheme, line-break and width facts, so a token
    // costs a single two-load lookup instead of three separate searches.
    // ASCII still skips the decode; it is one byte, one scalar.
    // ASCII keeps its direct arrays. The record is one load against these two,
    // but grapheme iteration then pays to extract line-break and width bits it
    // never reads; measured 5.6% slower on ascii/grapheme. All ASCII is one
    // column, which the exhaustive width check in root_test.zig pins.
    if (start < bytes.len and bytes[start] < 0x80) return .{
        .start = start,
        .end = start + 1,
        .codepoint = bytes[start],
        .grapheme = properties.grapheme_ascii[bytes[start]],
        .line_break = properties.line_break_ascii[bytes[start]],
        .cell_width = 1,
        .east_asian_wide = false, // No ASCII byte is East_Asian_Wide.
    };

    const step = utf8.step(bytes[start..]);
    if (step.cp) |cp| return fromCodepoint(start, start + step.len, cp);

    // Malformed input keeps its existing contract: one advancing AL-like
    // scalar with no code point and no columns.
    return malformedToken(start, start + step.len);
}

fn fromCodepoint(start: usize, end: usize, cp: u21) Token {
    return fromRecord(start, end, cp, properties.record(cp));
}

fn fromRecord(start: usize, end: usize, cp: u21, r: properties.Record) Token {
    return .{
        .start = start,
        .end = end,
        .codepoint = cp,
        .grapheme = properties.graphemeOf(r),
        .line_break = r.line_break,
        .cell_width = r.width,
        .east_asian_wide = r.east_asian_wide,
    };
}

pub fn codepointWidth(cp: u21) u2 {
    return properties.codepointWidth(cp);
}
