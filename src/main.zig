const std = @import("std");
const buffer = @import("core/gap.zig");
const terminal = @import("view/terminal.zig");
const keyboard = @import("view/keyboard.zig");
const utils = @import("utils.zig");
const Editor = @import("core/core.zig").Editor;
const Action = @import("core/core.zig").Action;
const PopBuilder = @import("core/core.zig").PopBuilder;
const Fs = @import("fs/filesystem.zig").Fs;

pub fn main(init: std.process.Init) !void {
    try terminal.enableRawMode();
    defer terminal.disableRawMode();

    const allocator = init.gpa;

    var stoudt_buf: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stoudt_buf);
    const stdout = &stdout_writer.interface;
    try terminal.openAlternateScreen(stdout);

    var dot = try Editor.init(allocator, init.io, init.environ_map);
    defer dot.deinit();
    dot.startLua();
    try dot.loadStandardKeyBinds();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next();
    if (args.next()) |filename| {
        try dot.loadFile(filename);

        if (Fs.loadFast(dot.allocator, filename)) |file_content| {
            defer allocator.free(file_content);
            const active_buf = dot.getActiveView().buf;
            active_buf.deinit();
            active_buf.* = try buffer.GapBuffer.initFromFile(dot.allocator, file_content, filename);
            _ = dot.triggerHook("BufInit");
        } else |err| {
            if (err != error.FileNotFound) {
                return err;
            }
        }
    }
    try dot.run(stdout);
    try terminal.closeAlternateScreen(stdout);
}
