const std = @import("std");
const buffer = @import("buffer/gap.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.print("[!] MEMORY LEAKS DETECTED", .{});
            std.posix.exit(42);
        }
    }

    const allocator = gpa.allocator();

    var buf = try buffer.GapBuffer.init(allocator);
    defer buf.deinit();

    try buf.insertChar('S');
    try buf.insertChar('a');
    try buf.insertChar('l');
    try buf.insertChar('u');
    try buf.insertChar('t');
    buf.printDebug();

    buf.moveCursorLeft();
    buf.moveCursorLeft();
    std.debug.print("move left\n", .{});

    try buf.insertChar('o');
    try buf.insertChar('p');
    std.debug.print("insert in middle\n", .{});
    buf.printDebug();

    buf.backspace();
    std.debug.print("backspace\n", .{});
    buf.printDebug();

    // std.debug.print("gap_buf.len: {d}\n", .{gap_buf.gap_end});
    // std.debug.print("{any}", .{gap_buf.buffer});
}
