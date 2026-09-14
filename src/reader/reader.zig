//! Allocation-free strict UTF-8 iteration over a caller-owned Reader.
const std = @import("std");
const codepoint_view = @import("cp");
const reader_graphemes = @import("graphemes.zig");

pub const ReaderCodepointError = error{
    ReadFailed,
    InvalidUtf8,
    ReaderBufferTooSmall,
    OffsetOverflow,
};

pub const Reader = struct {
    input: *std.Io.Reader,

    pub fn codepoints(self: Reader) ReaderCodepointIterator {
        return .{ .input = self.input };
    }

    /// Incrementally report the current grapheme after each decoded scalar.
    pub fn graphemes(self: Reader) ReaderGraphemeIterator {
        return .{ .points = self.codepoints() };
    }
};

pub fn init(input: *std.Io.Reader) Reader {
    return .{ .input = input };
}

const Status = enum {
    active,
    exhausted,
    read_failed,
    invalid_utf8,
    reader_buffer_too_small,
    offset_overflow,
};

pub const ReaderCodepointIterator = struct {
    pub const Error = ReaderCodepointError;

    const Decoded = struct {
        point: codepoint_view.CodepointView,
        raw: [4]u8,
        len: u3,
    };

    fn Result(comptime capture_bytes: bool) type {
        return if (capture_bytes) Decoded else codepoint_view.CodepointView;
    }

    input: *std.Io.Reader,
    offset: u64 = 0,
    status: Status = .active,

    // Let callers eliminate unused result/state handling, as slice iterators do.
    pub inline fn next(self: *ReaderCodepointIterator) ReaderCodepointError!?codepoint_view.CodepointView {
        return self.nextInternal(false);
    }

    /// Internal adapter entry point; capture bytes before advancing the Reader.
    inline fn nextDecoded(self: *ReaderCodepointIterator) ReaderCodepointError!?Decoded {
        return self.nextInternal(true);
    }

    inline fn nextInternal(self: *ReaderCodepointIterator, comptime capture_bytes: bool) ReaderCodepointError!?Result(capture_bytes) {
        switch (self.status) {
            .active => {},
            .exhausted => return null,
            .read_failed => return error.ReadFailed,
            .invalid_utf8 => return error.InvalidUtf8,
            .reader_buffer_too_small => return error.ReaderBufferTooSmall,
            .offset_overflow => return error.OffsetOverflow,
        }

        if (self.input.buffer.len == 0) return self.fail(.reader_buffer_too_small);
        const first = self.input.peek(1) catch |err| switch (err) {
            error.EndOfStream => {
                self.status = .exhausted;
                return null;
            },
            error.ReadFailed => return self.fail(.read_failed),
        };
        const lead = first[0];
        if (lead < 0x80) return try self.commit(capture_bytes, lead, 1);
        if (lead < 0xc2 or lead > 0xf4) return self.fail(.invalid_utf8);

        // Validate only the next decisive byte. A full-length peek could block
        // after an already-invalid prefix. Keep values, never slices, across
        // peeks: a refill may rebase the Reader's buffer.
        const second = try self.continuation(2);
        if ((lead == 0xe0 and second < 0xa0) or
            (lead == 0xed and second > 0x9f) or
            (lead == 0xf0 and second < 0x90) or
            (lead == 0xf4 and second > 0x8f)) return self.fail(.invalid_utf8);
        if (lead < 0xe0) return try self.commit(capture_bytes, (@as(u21, lead & 0x1f) << 6) | (second & 0x3f), 2);

        const third = try self.continuation(3);
        const tail = (@as(u21, second & 0x3f) << 6) | (third & 0x3f);
        if (lead < 0xf0) return try self.commit(capture_bytes, (@as(u21, lead & 0x0f) << 12) | tail, 3);

        const fourth = try self.continuation(4);
        return try self.commit(capture_bytes, (@as(u21, lead & 0x07) << 18) | (tail << 6) | (fourth & 0x3f), 4);
    }

    inline fn continuation(self: *ReaderCodepointIterator, comptime needed: usize) ReaderCodepointError!u8 {
        if (self.input.buffer.len < needed) return self.fail(.reader_buffer_too_small);
        const prefix = self.input.peek(needed) catch |err| switch (err) {
            error.EndOfStream => return self.fail(.invalid_utf8),
            error.ReadFailed => return self.fail(.read_failed),
        };
        const byte = prefix[needed - 1];
        if (byte & 0xc0 != 0x80) return self.fail(.invalid_utf8);
        return byte;
    }

    inline fn commit(self: *ReaderCodepointIterator, comptime capture_bytes: bool, value: u21, comptime length: usize) ReaderCodepointError!Result(capture_bytes) {
        const end = std.math.add(u64, self.offset, @as(u64, @intCast(length))) catch {
            return self.fail(.offset_overflow);
        };
        var result: Result(capture_bytes) = undefined;
        if (capture_bytes) {
            result = .{ .point = codepoint_view.init(value), .raw = .{ 0, 0, 0, 0 }, .len = length };
            @memcpy(result.raw[0..length], self.input.buffer[self.input.seek..][0..length]);
        } else {
            result = codepoint_view.init(value);
        }
        self.input.toss(length);
        self.offset = end;
        return result;
    }

    fn fail(self: *ReaderCodepointIterator, status: Status) ReaderCodepointError {
        self.status = status;
        return switch (status) {
            .read_failed => error.ReadFailed,
            .invalid_utf8 => error.InvalidUtf8,
            .reader_buffer_too_small => error.ReaderBufferTooSmall,
            .offset_overflow => error.OffsetOverflow,
            else => unreachable,
        };
    }
};

pub const ReaderGraphemeUpdate = reader_graphemes.Update;
pub const ReaderGraphemeError = ReaderCodepointError;
pub const ReaderGraphemeIterator = reader_graphemes.Iterator(ReaderCodepointIterator, ReaderCodepointIterator.nextDecoded);
