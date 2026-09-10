//! Turning bytes into scalars, and scalars into property records.
//!
//! `utf8` is the tolerant decoder every engine steps with; `scalar` pairs a
//! decoded scalar with the one table record that describes it; `ascii` is
//! the whole-slice byte-range check shared by word segmentation, `Text`,
//! and `Terminal`.
pub const utf8 = @import("utf8.zig");
pub const scalar = @import("scalar.zig");
pub const ascii = @import("ascii.zig");
