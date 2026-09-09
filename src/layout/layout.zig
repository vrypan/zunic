//! Fitting text to a terminal: column measurement and greedy wrapping.
//!
//! This is the only module that fuses the others. `scan` drives grapheme
//! segmentation, width and the line-break decision over a single pass, and
//! `wrap` consumes its clusters; `ascii` short-circuits input that needs
//! none of it.
pub const width = @import("width.zig");
pub const wrap = @import("wrap.zig");
pub const scan = @import("scan.zig");
pub const ascii = @import("ascii_scan.zig");
