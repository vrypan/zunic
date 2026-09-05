//! Internal, bounded detection of ASCII letter-only input.
const builtin = @import("builtin");
const options = @import("build_options");

pub const Backend = enum { off, scalar, auto, simd };

pub fn selectedBackend() Backend {
    return switch (options.wrap_fast_path) {
        .off => .off,
        .scalar => .scalar,
        .auto => .auto,
        .simd => .simd,
    };
}

/// Returns whether every byte is an ASCII letter. It never reads beyond bytes.
pub fn allLetters(bytes: []const u8) bool {
    return switch (selectedBackend()) {
        .off => false,
        .scalar => scalarAllLetters(bytes),
        .auto => if (simdSupported()) simdAllLetters(bytes) else scalarAllLetters(bytes),
        .simd => simdAllLetters(bytes),
    };
}

pub fn scalarAllLetters(bytes: []const u8) bool {
    for (bytes) |byte| if (!isLetter(byte)) return false;
    return true;
}

pub fn simdAllLetters(bytes: []const u8) bool {
    if (!simdSupported()) return scalarAllLetters(bytes);
    const width = 16;
    var index: usize = 0;
    while (index + width <= bytes.len) : (index += width) {
        const chunk: @Vector(width, u8) = bytes[index..][0..width].*;
        const lower = chunk | @as(@Vector(width, u8), @splat(0x20));
        const letters = (lower >= @as(@Vector(width, u8), @splat('a'))) & (lower <= @as(@Vector(width, u8), @splat('z')));
        if (!@reduce(.And, letters)) return scalarAllLetters(bytes[index..][0..width]);
    }
    return scalarAllLetters(bytes[index..]);
}

pub fn simdSupported() bool {
    return switch (builtin.cpu.arch) {
        .aarch64, .x86_64 => true,
        else => false,
    };
}

fn isLetter(byte: u8) bool {
    const lower = byte | 0x20;
    return lower >= 'a' and lower <= 'z';
}
