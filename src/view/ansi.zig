const std = @import("std");
pub const hide_cursor = "\x1b[?25l";
pub const show_cursor = "\x1b[?25h";
pub const clear_screen = "\x1b[2J\x1b[H";

pub fn goto(writer: *std.Io.Writer, row: usize, col: usize) !void {
    try writer.print("\x1b[{d};{d}H", .{ row, col });
}
