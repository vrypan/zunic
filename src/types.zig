//! Shared public byte positions and display measurements. No engine dependencies.
pub const ByteOffset = struct {
    value: usize,
};

pub const Column = struct {
    value: usize,
};

pub const Span = struct {
    start: ByteOffset,
    end: ByteOffset,
};

pub const MeasuredSpan = struct {
    start: ByteOffset,
    end: ByteOffset,
    columns: u2,
    renderable: bool,
};
