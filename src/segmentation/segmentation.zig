//! Where text divides: UAX #29 grapheme clusters and word boundaries.
//!
//! The two engines share no state and no tables with each other; they are
//! grouped because they answer the same shape of question.
pub const grapheme = @import("grapheme.zig");
pub const word = @import("word.zig");
