const std = @import("std");
const zui = @import("zui");
const buffer = @import("core/gap.zig");
const terminal = @import("view/terminal.zig");
const keyboard = @import("view/keyboard.zig");
const utils = @import("utils.zig");
const Editor = @import("core/core.zig").Editor;
const Window = @import("core/core.zig").Window;
const Action = @import("core/core.zig").Action;
const PopBuilder = @import("core/core.zig").PopBuilder;
const Fs = @import("fs/filesystem.zig").Fs;

pub fn main(init: std.process.Init) !void {
    try terminal.enableRawMode();
    defer terminal.disableRawMode();

    const allocator = init.gpa;

    var stout_buf: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stout_buf);
    const stdout = &stdout_writer.interface;

    const win = try Window.init();
    var zui_term = try zui.terminal.Terminal.init(allocator, stdout, win.cols, win.rows);
    defer zui_term.deinit();

    var dot = try Editor.init(allocator, init.io, init.environ_map);
    defer dot.deinit();
    dot.startLua();
    try dot.loadStandardKeyBinds();

    var args = init.minimal.args;
    var args_it = args.iterate();
    _ = args_it.next();
    if (args_it.next()) |filename| {
        try dot.loadFile(filename);

        if (Fs.loadFast(dot.allocator, init.io, filename)) |file_content| {
            defer allocator.free(file_content);
            const active_buf = dot.getActiveView().buf;
            active_buf.deinit();
            active_buf.* = try buffer.GapBuffer.initFromFile(dot.allocator, init.io, file_content, filename);
            _ = dot.triggerHook("BufInit");
        } else |err| {
            if (err != error.FileNotFound) {
                return err;
            }
        }
    }
    try dot.run(&zui_term);
}
