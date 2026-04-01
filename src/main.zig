const std = @import("std");
const buffer = @import("core/gap.zig");
const terminal = @import("view/terminal.zig");
const keyboard = @import("view/keyboard.zig");
const ui = @import("view/ui.zig");
const utils = @import("utils.zig");
const Editor = @import("core/core.zig").Editor;
const Action = @import("core/core.zig").Action;
const PopBuilder = @import("core/core.zig").PopBuilder;
const Fs = @import("fs/filesystem.zig").Fs;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.print("[!] MEMORY LEAKS DETECTED", .{});
            std.posix.exit(42);
        }
    }

    try terminal.enableRawMode();
    defer terminal.disableRawMode();

    const allocator = gpa.allocator();

    var stoudt_buf: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stoudt_buf);
    const stdout = &stdout_writer.interface;
    try terminal.openAlternateScreen(stdout);

    var dot = try Editor.init(allocator);
    defer dot.deinit();
    try dot.loadStandardKeyBinds();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next();
    if (args.next()) |filename| {
        dot.loadFile(filename);

        if (Fs.loadFast(dot.allocator, filename)) |file_content| {
            defer allocator.free(file_content);
            const active_buf = dot.getActiveView().buf;
            active_buf.deinit();
            active_buf.* = try buffer.GapBuffer.initFromFile(dot.allocator, file_content);
        } else |err| {
            if (err != error.FileNotFound) {
                return err;
            }
        }
    }
    try dot.run(stdout);
    try terminal.closeAlternateScreen(stdout);
}
