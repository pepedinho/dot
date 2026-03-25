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

    var current_row: usize = 1;
    var current_col: usize = 1;
    var screen_row: usize = 1;
    const max_rows = editor.win.rows - 1;
    const parts = [_][]const u8{ part1, part2 };
    for (parts) |part| {
        for (part) |c| {
            if (screen_row > max_rows) break;

            if (c == '\n') {
                if (current_row > editor.row_offset) {
                    try stdout.writeAll("\r\n");
                    screen_row += 1;
                }
                current_row += 1;
                current_col = 1;
            } else if (c == '\t') {
                const TAB_SIZE = 8;
                for (0..TAB_SIZE) |_| {
                    if (current_row > editor.row_offset) {
                        if (current_col > editor.col_offset and current_col <= editor.col_offset + editor.win.cols) {
                            try stdout.writeAll(" ");
                        }
                    }
                    current_col += 1;
                }
            } else {
                if (current_row > editor.row_offset) {
                    if (current_col > editor.col_offset and current_col <= editor.col_offset + editor.win.cols) {
                        try stdout.writeAll(&[_]u8{c});
                    }
                }
                current_col += 1;
            }
        }
    }

    try displayMode(stdout, editor);
    if (editor.mode == .Command) {
        try commandPrompt(stdout, editor);
    } else {
        const pos = editor.buf.getCursorPos();

        const screen_y = pos.y - editor.row_offset;
        const screen_x = pos.x - editor.col_offset;

        try stdout.print("\x1b[{d};{d}H", .{ screen_y, screen_x });
    }
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

pub fn updateCurrentLine(stdout: *std.Io.Writer, editor: *Editor) !void {
    const buf = &editor.buf;
    const pos = buf.getCursorPos();

    const screen_y = pos.y - editor.row_offset;
    const screen_x = pos.x - editor.col_offset;

    try stdout.writeAll("\x1b[?25l");
    try stdout.print("\x1b[{d};1H\x1b[2K", .{screen_y});

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
    try stdout.print("\x1b[{d};{d}H\x1b[?25h", .{ screen_y, screen_x });
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
