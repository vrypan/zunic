//! Internal, bounded detection of ASCII letter-only input.
const builtin = @import("builtin");
const options = @import("build_options");

pub const Backend = enum { off, scalar, auto, simd };
pub const Paragraph = enum { none, letters, simple };
const simd_width = 16;

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
        // Auto is enabled only for native ARM64, where this backend has been
        // exercised. x86 stays scalar until it has actual-hardware coverage.
        .auto => if (autoSimdSupported() and bytes.len >= simd_width) simdAllLetters(bytes) else scalarAllLetters(bytes),
        .simd => simdAllLetters(bytes),
    };
}

/// Recognizes the ASCII subset whose grapheme and line-break behavior is
/// fully represented by letters, spaces, and hard separators.
pub fn paragraph(bytes: []const u8) Paragraph {
    if (selectedBackend() == .off) return .none;
    if (allLetters(bytes)) return .letters;
    for (bytes) |byte| switch (byte) {
        'a'...'z', 'A'...'Z', ' ', '\n', '\r', 0x0B, 0x0C => {},
        else => return .none,
    };
    return .simple;
}

pub fn scalarAllLetters(bytes: []const u8) bool {
    for (bytes) |byte| if (!isLetter(byte)) return false;
    return true;
}

pub fn simdAllLetters(bytes: []const u8) bool {
    if (!simdSupported()) return scalarAllLetters(bytes);
    var index: usize = 0;
    while (index + simd_width <= bytes.len) : (index += simd_width) {
        const chunk: @Vector(simd_width, u8) = bytes[index..][0..simd_width].*;
        const lower = chunk | @as(@Vector(simd_width, u8), @splat(0x20));
        const letters = (lower >= @as(@Vector(simd_width, u8), @splat('a'))) & (lower <= @as(@Vector(simd_width, u8), @splat('z')));
        if (!@reduce(.And, letters)) return scalarAllLetters(bytes[index..][0..simd_width]);
    }
    return scalarAllLetters(bytes[index..]);
}

pub fn simdSupported() bool {
    return switch (builtin.cpu.arch) {
        .aarch64, .x86_64 => true,
        else => false,
    };
}

fn autoSimdSupported() bool {
    return builtin.cpu.arch == .aarch64;
}

fn isLetter(byte: u8) bool {
    const lower = byte | 0x20;
    return lower >= 'a' and lower <= 'z';
}
