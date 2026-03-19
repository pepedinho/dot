const std = @import("std");

var original_termios: std.posix.termios = undefined;

pub fn enableRawMode() !void {
    const stdin = std.posix.STDIN_FILENO;

    original_termios = try std.posix.tcgetattr(stdin);
    var raw = original_termios;

    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    raw.lflag.ISIG = false;
    raw.lflag.IEXTEN = false;

    raw.iflag.IXON = false;
    raw.iflag.ICRNL = false;
    raw.iflag.BRKINT = false;
    raw.iflag.INPCK = false;
    raw.iflag.ISTRIP = false;

    raw.oflag.OPOST = false;

    try std.posix.tcsetattr(stdin, .FLUSH, raw);
}

pub fn disableRawMode() void {
    const stdin = std.posix.STDIN_FILENO;
    std.posix.tcsetattr(stdin, .FLUSH, original_termios) catch return;
}
