const std = @import("std");
pub const Pos = struct { x: usize, y: usize };

pub fn isDigitSlice(s: []const u8) bool {
    for (s) |c| {
        if (!std.ascii.isDigit(c))
            return false;
    }
    return s.len > 0;
}

pub fn parseKeyString(key_str: []const u8) ?u8 {
    if (key_str.len == 0) return null;

    if (key_str.len == 1) return key_str[0];

    if (key_str[0] == '<' and key_str[key_str.len - 1] == '>') {
        const inner = key_str[1 .. key_str.len - 1];

        if (inner.len == 3 and inner[0] == 'C' and inner[1] == '-') {
            const char = inner[2];
            if (char >= 'a' and char <= 'z') {
                return char - 'a' + 1;
            }
            if (char >= 'A' and char <= 'Z') {
                return char - 'A' + 1;
            }
        }

        if (std.mem.eql(u8, inner, "CR")) return '\r';
        if (std.mem.eql(u8, inner, "Esc")) return '\x1b';
    }
    return null;
}
