const std = @import("std");
const buffer = @import("../buffer/gap.zig");
const Editor = @import("../buffer/core.zig").Editor;
const utils = @import("../utils.zig");

const MODE = [_][]const u8{ "NORMAL", "INSERT", "COMMAND" };
const MODE_COLOR = [_][]const u8{ "\x1b[0;106m", "\x1b[0;102m", "\x1b[0;101m" };

pub fn refreshScreen(stdout: *std.Io.Writer, editor: *Editor) !void {
    try stdout.writeAll("\x1b[?25l");
    try stdout.writeAll("\x1b[2J\x1b[H");

    const part1 = editor.buf.getFirst();
    const part2 = editor.buf.getSecond();

    try writeWithCTRLF(stdout, part1);
    try writeWithCTRLF(stdout, part2);

    const pos = editor.buf.getCursorPos();

    try stdout.print("\x1b[{d};{d}H", .{ pos.y, pos.x });

    try displayMode(stdout, editor);
    if (editor.mode == .Command) {
        // try stdout.print(":{s}", .{editor.cmd_buf.items});
        // try insertLine(stdout, editor.cmd_buf.items, editor.win.rows - 2);
        try commandPrompt(stdout, editor);
    }
    try stdout.writeAll("\x1b[?25h"); // display cursor
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

pub fn displayMode(stdout: *std.Io.Writer, editor: *Editor) !void {
    const last_pos = editor.buf.getCursorPos();
    const win = editor.win;

    try stdout.print("\x1b[{d};1H\x1b[2K", .{win.rows});
    const mode = @intFromEnum(editor.mode);
    try stdout.print("{s} {s} \x1b[m", .{ MODE_COLOR[mode], MODE[mode] });
    try stdout.print("\x1b[{d};{d}H", .{ last_pos.y, last_pos.x });
}

pub fn insertLine(stdout: *std.Io.Writer, text: []const u8, row: usize) !void {
    try stdout.writeAll("\x1b[?25h"); // display cursor
    try stdout.print("\x1b[{d};1H\x1b[2K", .{row});
    try stdout.print("{s}\x1b[m", .{text});
}

pub fn commandPrompt(stdout: *std.Io.Writer, editor: *Editor) !void {
    const row = editor.win.rows;
    const text = editor.cmd_buf.items;
    const cols = editor.win.cols;

    try stdout.print("\x1b[{d};1H\x1b[48;5;237m", .{row});

    try stdout.print(":{s}", .{text});

    const used_cols = text.len + 1;
    if (cols > used_cols) {
        for (0..cols - used_cols) |_| {
            try stdout.writeByte(' ');
        }
    }

    try stdout.writeAll("\x1b[m");

    try stdout.print("\x1b[{d};{d}H", .{ row, used_cols + 1 });
}
