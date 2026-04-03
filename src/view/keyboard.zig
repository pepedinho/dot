const std = @import("std");

pub const Key = union(enum) {
    ascii: u8,
    up,
    down,
    right,
    left,
    backspace,
    enter,
    escape,
    none,
};

/// Reads a single keystroke from standard input (stdin) in raw (non-blocking) mode.
/// This function handles standard ASCII characters as well as multi-byte
/// ANSI escape sequences (such as arrow keys).
///
/// Returns `.none` if no character is currently available in the buffer.
pub fn readKey() !Key {
    var buf: [1]u8 = undefined;

    const byte_read = try std.posix.read(std.posix.STDIN_FILENO, &buf);

    if (byte_read == 0) return .none;

    const c = buf[0];

    if (c == '\x1b') {
        var seq: [2]u8 = undefined;

        if ((try std.posix.read(std.posix.STDIN_FILENO, seq[0..1])) == 0) return .escape;
        if ((try std.posix.read(std.posix.STDIN_FILENO, seq[1..2])) == 0) return .escape;

        if (seq[0] == '[') {
            switch (seq[1]) {
                'A' => return .up,
                'B' => return .down,
                'C' => return .right,
                'D' => return .left,
                else => return .escape,
            }
        }
        return .escape;
    } else if (c == 127) {
        return .backspace;
    } else if (c == '\r') {
        return .enter;
    } else {
        return .{ .ascii = c };
    }
}
