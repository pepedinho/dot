const std = @import("std");
const buffer = @import("../buffer/gap.zig");
const Editor = @import("../buffer/core.zig").Editor;

pub fn refreshScreen(stdout: *std.Io.Writer, buf: *buffer.GapBuffer) !void {
    try stdout.writeAll("\x1b[?25l");
    try stdout.writeAll("\x1b[2J\x1b[H");

    const part1 = buf.getFirst();
    const part2 = buf.getSecond();

    try writeWithCTRLF(stdout, part1);
    try writeWithCTRLF(stdout, part2);

    const pos = buf.getCursorPos();

    try stdout.print("\x1b[{d};{d}H", .{ pos.y, pos.x });
    try stdout.writeAll("\x1b[?25h");
}

fn writeWithCTRLF(stdout: *std.Io.Writer, text: []const u8) !void {
    var start: usize = 0;

    for (text, 0..) |c, i| {
        if (c == '\n') {
            try stdout.writeAll(text[start..i]);
            try stdout.writeAll("\r\n");
            start = i + 1;
        }
    }

    if (start < text.len) {
        try stdout.writeAll(text[start..text.len]);
    }
}

pub fn updateCurrentLine(stdout: *std.Io.Writer, buf: *buffer.GapBuffer) !void {
    const pos = buf.getCursorPos();
    try stdout.writeAll("\x1b[?25l");
    try stdout.print("\x1b[{d};1H\x1b[2K", .{pos.y});

    var start_of_line = buf.gap_start;
    while (start_of_line > 0 and buf.buffer[start_of_line - 1] != '\n') {
        start_of_line -= 1;
    }

    try stdout.writeAll(buf.buffer[start_of_line..buf.gap_start]);

    var end_of_line = buf.gap_end;
    while (end_of_line < buf.buffer.len and buf.buffer[end_of_line] != '\n') {
        end_of_line += 1;
    }

    try stdout.writeAll(buf.buffer[buf.gap_end..end_of_line]);
    try stdout.print("\x1b[{d};{d}H\x1b[?25h", .{ pos.y, pos.x });
}

// pub fn displayMode(stdout: *std.Io.Writer, editor: *Editor) !void {

// }
