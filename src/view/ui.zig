const std = @import("std");
const buffer = @import("../buffer/gap.zig");

pub fn refreshScreen(stdout: *std.Io.Writer, buf: *buffer.GapBuffer) !void {
    try stdout.writeAll("\x1b[?25l");
    try stdout.writeAll("\x1b[2J\x1b[H");

    const part1 = buf.getFirst();
    const part2 = buf.getSecond();

    try stdout.writeAll(part1);
    try stdout.writeAll(part2);

    var cursor_x: usize = 1;
    var cursor_y: usize = 1;

    for (part1) |c| {
        if (c == '\n') {
            cursor_y += 1;
            cursor_x = 1;
        } else {
            cursor_x += 1;
        }
    }

    try stdout.print("\x1b[{d};{d}H", .{ cursor_y, cursor_x });

    try stdout.writeAll("\x1b[?25h");
}
