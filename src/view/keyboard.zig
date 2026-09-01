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
    var buf: [1]u8 = undefined;

    const byte_read = try std.posix.read(std.posix.STDIN_FILENO, &buf);

    if (byte_read == 0) return .none;

    if (zui.EventParser.parse(buf[0..1])) |result| {
        return mapKeyCode(result.event.key.code);
    }

    return .none;
}
