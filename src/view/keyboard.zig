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

fn mapKeyCode(ev: zui.event.KeyEvent) Key {
    return switch (ev.code) {
        .char => |c| {
            if (ev.modifiers.control and c <= 127) {
                if (c >= 'a' and c <= 'z') return .{ .ascii = @intCast(c - 'a' + 1) };
                if (c >= 'A' and c <= 'Z') return .{ .ascii = @intCast(c - 'A' + 1) };
                if (c == '@') return .{ .ascii = 0 };
                if (c == '[') return .{ .ascii = 27 };
            }
            if (c <= 127) return .{ .ascii = @intCast(c) };
            return .none;
        },
        .tab => .{ .ascii = 0x09 },
        .up => .up,
        .down => .down,
        .right => .right,
        .left => .left,
        .back_tab => .shift_tab,
        .backspace => .backspace,
        .enter => .enter,
        .esc => .escape,
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
        return mapKeyCode(result.event.key);
    }

    return .none;
}

test "mapKeyCode restores tab and ctrl mappings" {
    const k = zui.event.KeyEvent;
    const tab = mapKeyCode(k{ .code = .tab });
    try std.testing.expectEqual(Key{ .ascii = 0x09 }, tab);

    const ctrl_s = mapKeyCode(k{ .code = .{ .char = 's' }, .modifiers = .{ .control = true } });
    try std.testing.expectEqual(Key{ .ascii = 0x13 }, ctrl_s);

    const ctrl_at = mapKeyCode(k{ .code = .{ .char = '@' }, .modifiers = .{ .control = true } });
    try std.testing.expectEqual(Key{ .ascii = 0 }, ctrl_at);

    const plain = mapKeyCode(k{ .code = .{ .char = 'd' } });
    try std.testing.expectEqual(Key{ .ascii = 'd' }, plain);

    const shift_tab = mapKeyCode(k{ .code = .back_tab });
    try std.testing.expectEqual(Key.shift_tab, shift_tab);
}
