const std = @import("std");
const buffer = @import("buffer/gap.zig");
const terminal = @import("view/terminal.zig");
const keyboard = @import("view/keyboard.zig");
const ui = @import("view/ui.zig");
const utils = @import("utils.zig");
const Editor = @import("buffer/core.zig").Editor;
const Action = @import("buffer/core.zig").Action;
const PopBuilder = @import("buffer/core.zig").PopBuilder;
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
            dot.buf.deinit();
            defer allocator.free(file_content);
            dot.buf = try buffer.GapBuffer.initFromFile(allocator, file_content);
        } else |err| {
            if (err != error.FileNotFound) {
                return err;
            }
        }
    }

    while (dot.is_running) {
        if (dot.scroll()) {
            dot.needs_redraw = true;
        }

        if (dot.needs_redraw) {
            try ui.refreshScreen(stdout, &dot);
        } else {
            try ui.updateCurrentLine(stdout, &dot);
        }

        // try dot.renderAllPopup(stdout);

        try stdout.flush();

        const key = try keyboard.readKey();
        // if (key == .none) continue;

        // var action: ?Action = null;
        // std.debug.print("{any}", .{key});

        if (key == .none) {
            try dot.pushAction(.Tick);
        } else {
            switch (dot.mode) {
                .Normal => {
                    switch (key) {
                        .ascii => |c| {
                            if (dot.key_binds.get(c)) |a| {
                                try dot.pushAction(a);
                            }
                        },
                        .left => try dot.pushAction(.MoveLeft),
                        .right => try dot.pushAction(.MoveRight),
                        .down => try dot.pushAction(.MoveDown),
                        .up => try dot.pushAction(.MoveUp),
                        else => {},
                    }
                },
                .Insert => {
                    switch (key) {
                        .escape => try dot.pushAction(.{ .SetMode = .Normal }),
                        .ascii => |c| try dot.pushAction(.{ .InsertChar = c }),
                        .enter => try dot.pushAction(.InsertNewLine),
                        .backspace => try dot.pushAction(.DeleteChar),
                        .left => try dot.pushAction(.MoveLeft),
                        .right => try dot.pushAction(.MoveRight),
                        .up => try dot.pushAction(.MoveUp),
                        .down => try dot.pushAction(.MoveDown),
                        else => {},
                    }
                },
                .Command => {
                    switch (key) {
                        .escape => try dot.pushAction(.{ .SetMode = .Normal }),
                        .ascii => |c| {
                            try dot.pushAction(.{ .CommandChar = c });
                        },
                        .backspace => try dot.pushAction(.CommandBackspace),
                        .enter => try dot.pushAction(.ExecuteCommand),
                        else => {},
                    }
                },
            }
        }

        while (dot.action_queue.pop()) |act| {
            try dot.execute(act);
        }
        try dot.win.updateSize();
    }
    try terminal.closeAlternateScreen(stdout);
    // try stdout.writeAll("\x1b[H\x1b[2J\x1b[3J");
}
