const std = @import("std");
const buffer = @import("../buffer/gap.zig");
const Editor = @import("../buffer/core.zig").Editor;
const utils = @import("../utils.zig");
const ansi = @import("ansi.zig");
const View = @import("../buffer/pane.zig").View;

const MODE = [_][]const u8{ "NORMAL", "INSERT", "COMMAND" };
const MODE_COLOR = [_][]const u8{ "\x1b[0;106m", "\x1b[0;102m", "\x1b[0;101m" };

fn renderView(stdout: *std.Io.Writer, view: *const View) !void {
    const part1 = view.buf.getFirst();
    const part2 = view.buf.getSecond();

    var current_row: usize = 1;
    var current_col: usize = 1;

    var screen_row = view.y;
    const max_rows = view.y + view.height - 1;

    const clear_to_eol = "\x1b[K";
    try ansi.goto(stdout, screen_row, view.x);

    const parts = [_][]const u8{ part1, part2 };
    for (parts) |part| {
        for (part) |c| {
            if (screen_row > max_rows) break;

            if (c == '\n') {
                if (current_row > view.row_offset) {
                    try stdout.writeAll(clear_to_eol);
                    // try stdout.writeAll("\r\n");
                    screen_row += 1;
                    if (screen_row <= max_rows) {
                        try ansi.goto(stdout, screen_row, view.x);
                    }
                }
                current_row += 1;
                current_col = 1;
            } else if (c == '\t') {
                const TAB_SIZE = 8;
                for (0..TAB_SIZE) |_| {
                    if (current_row > view.row_offset) {
                        if (current_col > view.col_offset and current_col <= view.col_offset + view.width) {
                            // try ansi.goto(stdout, screen_row, view.x + current_col - view.col_offset - 1);
                            try stdout.writeAll(" ");
                        }
                    }
                    current_col += 1;
                }
            } else {
                if (current_row > view.row_offset) {
                    if (current_col > view.col_offset and current_col <= view.col_offset + view.width) {
                        // try ansi.goto(stdout, screen_row, view.x + current_col - view.col_offset - 1);
                        try stdout.writeAll(&[_]u8{c});
                    }
                }
                current_col += 1;
            }
        }
    }

    while (screen_row <= max_rows) : (screen_row += 1) {
        try ansi.goto(stdout, screen_row, view.x);
        try stdout.writeAll(clear_to_eol);
    }
}

pub fn refreshScreen(stdout: *std.Io.Writer, editor: *Editor) !void {
    try stdout.writeAll(ansi.hide_cursor);
    try stdout.writeAll(ansi.clear_screen);

    try renderView(stdout, &editor.active_view);

    try displayMode(stdout, editor);
    try editor.renderAllPopup(stdout);

    if (editor.mode == .Command) {
        try commandPrompt(stdout, editor);
    } else {
        const pos = editor.active_view.buf.getCursorPos();
        const screen_y = editor.active_view.y + pos.y - editor.active_view.row_offset - 1;
        const screen_x = editor.active_view.x + pos.x - editor.active_view.col_offset - 1;

        try ansi.goto(stdout, screen_y, screen_x);
    }

    try stdout.writeAll(ansi.show_cursor);
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

    const screen_y = pos.y - editor.active_view.row_offset;
    const screen_x = pos.x - editor.active_view.col_offset;

    try stdout.writeAll(ansi.hide_cursor);
    try ansi.goto(stdout, screen_y, 1);

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

    // Z-Index for pop box
    var it = editor.pop_store.valueIterator();
    while (it.next()) |p| {
        const pop_top = p.pos.y;
        const pop_bottom = p.pos.y + p.size.y - 1;

        if (screen_y >= pop_top and screen_y <= pop_bottom) {
            try @import("pop.zig").render(stdout, p);
        }
    }

    try ansi.goto(stdout, screen_y, screen_x);
    try stdout.writeAll(ansi.show_cursor);
}

pub fn displayMode(stdout: *std.Io.Writer, editor: *Editor) !void {
    const last_pos = editor.buf.getCursorPos();
    const win = editor.win;

    try stdout.print("\x1b[{d};1H\x1b[2K", .{win.rows});
    const mode = @intFromEnum(editor.mode);
    try stdout.print("{s} {s} \x1b[m", .{ MODE_COLOR[mode], MODE[mode] });
    try ansi.goto(stdout, last_pos.y, last_pos.x);
}

pub fn insertLine(stdout: *std.Io.Writer, text: []const u8, row: usize) !void {
    try stdout.writeAll(ansi.show_cursor); // display cursor
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
