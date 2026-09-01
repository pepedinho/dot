const std = @import("std");
const zui = @import("zui");

pub const Key = union(enum) {
    ascii: u8,
    up,
    down,
    right,
    left,
    shift_tab,
    backspace,
    enter,
    escape,
    none,
};

fn mapKeyCode(code: zui.event.KeyCode) Key {
    return switch (code) {
        .up => .up,
        .down => .down,
        .right => .right,
        .left => .left,
        .back_tab => .shift_tab,
        .backspace => .backspace,
        .enter => .enter,
        .esc => .escape,
        .char => |c| {
            if (c <= 127) return .{ .ascii = @intCast(c) };
            return .none;
        },
        else => .none,
    };
}

pub fn readKey() !Key {
    var buf: [32]u8 = undefined;

    const byte_read = try std.posix.read(std.posix.STDIN_FILENO, buf[0..1]);
    if (byte_read == 0) return .none;

    var total: usize = 1;

    if (buf[0] == 0x1B) {
        while (total < buf.len) {
            const n = try std.posix.read(std.posix.STDIN_FILENO, buf[total..]);
            if (n == 0) break;
            total += n;
        }
    }

    if (zui.EventParser.parse(buf[0..total])) |result| {
        return mapKeyCode(result.event.key.code);
    }

    return .none;
}
