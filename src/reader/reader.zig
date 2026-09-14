//! Allocation-free strict UTF-8 iteration over a caller-owned Reader.
const std = @import("std");
const codepoint_view = @import("cp");
const encoding = @import("encoding");

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
    input: *std.Io.Reader,
    offset: u64 = 0,
    status: Status = .active,

    pub fn next(self: *ReaderCodepointIterator) ReaderCodepointError!?codepoint_view.CodepointView {
        switch (self.status) {
            .active => {},
            .exhausted => return null,
            .read_failed => return error.ReadFailed,
            .invalid_utf8 => return error.InvalidUtf8,
            .reader_buffer_too_small => return error.ReaderBufferTooSmall,
            .offset_overflow => return error.OffsetOverflow,
        }

        var needed: usize = 1;
        while (true) {
            if (self.input.buffer.len < needed)
                return self.fail(.reader_buffer_too_small);

            const prefix = self.input.peek(needed) catch |err| switch (err) {
                error.EndOfStream => {
                    if (needed == 1) {
                        self.status = .exhausted;
                        return null;
                    }
                    return self.fail(.invalid_utf8);
                },
                error.ReadFailed => return self.fail(.read_failed),
            };
            switch (encoding.utf8_prefix.classify(prefix)) {
                .invalid => return self.fail(.invalid_utf8),
                .incomplete => |next_needed| needed = next_needed,
                .complete => |length| {
                    const decoded = encoding.utf8.step(prefix);
                    const value = decoded.cp orelse return self.fail(.invalid_utf8);
                    if (decoded.len != length) return self.fail(.invalid_utf8);
                    const end = std.math.add(u64, self.offset, @as(u64, @intCast(length))) catch
                        return self.fail(.offset_overflow);
                    self.input.toss(length);
                    self.offset = end;
                    return codepoint_view.init(value);
                },
            }
        }
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
