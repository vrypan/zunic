const std = @import("std");

// Volatile inputs prevent the optimizer from replacing the probe with a
// compile-time constant while keeping command-line and I/O code out of all
// three size measurements.
var first_input: u21 = 0x1f600;
var second_input: u21 = 0x0301;

pub fn main() void {
    const first: *volatile u21 = &first_input;
    const second: *volatile u21 = &second_input;
    var checksum: u64 = first.*;
    checksum *%= 0x100000001b3;
    checksum ^= second.*;
    std.mem.doNotOptimizeAway(checksum);
}
