const std = @import("std");
pub const Pos = struct { x: usize, y: usize };

pub fn isDigitSlice(s: []const u8) bool {
    for (s) |c| {
        if (!std.ascii.isDigit(c))
            return false;
    }
    return true;
}
