//! Byte-only recognition of complete 7-bit CSI and OSC sequences.
//! Callers pass a valid byte offset to end(), and a recognized escape to isSgr().
pub fn isSgr(bytes: []const u8) bool {
    if (bytes[1] != '[' or bytes[bytes.len - 1] != 'm') return false;
    for (bytes[2 .. bytes.len - 1]) |byte| {
        if (!(byte >= '0' and byte <= '9') and byte != ';' and byte != ':') return false;
    }
    return true;
}

// Recognize only complete 7-bit CSI and OSC sequences. Unsupported or broken
// sequences fall back to ordinary text. An unexpected ESC aborts recognition,
// so repeated unterminated introducers cannot cause quadratic rescanning.
pub inline fn end(bytes: []const u8, start: usize) ?usize {
    if (bytes[start] != 0x1b or bytes.len - start < 2) return null;
    var pos = start + 2;
    switch (bytes[start + 1]) {
        '[' => {
            while (pos < bytes.len and bytes[pos] >= 0x30 and bytes[pos] <= 0x3f) : (pos += 1) {}
            while (pos < bytes.len and bytes[pos] >= 0x20 and bytes[pos] <= 0x2f) : (pos += 1) {}
            if (pos < bytes.len and bytes[pos] >= 0x40 and bytes[pos] <= 0x7e) return pos + 1;
            return null;
        },
        ']' => {
            while (pos < bytes.len) : (pos += 1) {
                const byte = bytes[pos];
                if (byte == 0x07) return pos + 1;
                if (byte == 0x1b) {
                    if (bytes.len - pos >= 2 and bytes[pos + 1] == '\\') return pos + 2;
                    return null;
                }
                // This first draft accepts printable payload bytes (including
                // UTF-8), not embedded C0 controls or DEL.
                if (byte < 0x20 or byte == 0x7f) return null;
            }
            return null;
        },
        else => return null,
    }
}
