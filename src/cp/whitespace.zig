/// Unicode 17.0.0 `White_Space=Yes`, as published in UCD `PropList.txt`.
///
/// Exactly 25 code points. This is not general category `Zs`, not
/// `Pattern_White_Space`, not the zero-width set, and not the UAX #14 hard
/// terminators: U+00A0 and U+202F are trimmed although they are no-break, and
/// U+200B, U+FEFF, U+180E and U+2060 are not trimmed although they render as
/// nothing.
pub fn isWhitespace(cp: u21) bool {
    return switch (cp) {
        0x0009...0x000D,
        0x0020,
        0x0085,
        0x00A0,
        0x1680,
        0x2000...0x200A,
        0x2028,
        0x2029,
        0x202F,
        0x205F,
        0x3000,
        => true,
        else => false,
    };
}
