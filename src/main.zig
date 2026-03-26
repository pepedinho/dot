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
        if (dot.needs_redraw) {
            dot.scroll();
            try ui.refreshScreen(stdout, &dot);
        } else {
            dot.scroll();
            try ui.updateCurrentLine(stdout, &dot);
        }

        try dot.renderAllPopup(stdout);

        try stdout.flush();

        const key = try keyboard.readKey();
        // if (key == .none) continue;

        var action: ?Action = null;
        // std.debug.print("{any}", .{key});

        if (key == .none) {
            action = .Tick;
        } else {
            switch (dot.mode) {
                .Normal => {
                    switch (key) {
                        .ascii => |c| {
                            if (c == 'i') action = .{ .SetMode = .Insert };
                            if (c == 'h') action = .MoveLeft;
                            if (c == 'j') action = .MoveDown;
                            if (c == 'k') action = .MoveUp;
                            if (c == 'l') action = .MoveRight;
                            if (c == 'a') action = .Append;
                            if (c == 'o') action = .AppendNewLine;
                            if (c == 'x') action = .DeleteChar;
                            if (c == 'q') action = .Quit;
                            if (c == ':') action = .{ .SetMode = .Command };
                        },
                        .left => action = .MoveLeft,
                        .right => action = .MoveRight,
                        .down => action = .MoveDown,
                        .up => action = .MoveUp,
                        else => {},
                    }
                },
                .Insert => {
                    switch (key) {
                        .escape => action = .{ .SetMode = .Normal },
                        .ascii => |c| action = .{ .InsertChar = c },
                        .enter => action = .InsertNewLine,
                        .backspace => action = .DeleteChar,
                        .left => action = .MoveLeft,
                        .right => action = .MoveRight,
                        .up => action = .MoveUp,
                        .down => action = .MoveDown,
                        else => {},
                    }
                },
                .Command => {
                    switch (key) {
                        .escape => action = .{ .SetMode = .Normal },
                        .ascii => |c| {
                            // if (c == 'p') {
                            //     const size = dot.win;
                            //     const text = "test";
                            //     const pos = utils.Pos{ .x = size.cols / 2, .y = size.rows / 2 };
                            //     const pop = PopBuilder{
                            //         .pos = pos,
                            //         .size = .{ .x = 20, .y = 5 },
                            //         .text = text,
                            //         .duration_ms = 2000,
                            //     };
                            //     action = .{ .CreatePop = pop };
                            // }
                            action = .{ .CommandChar = c };
                        },
                        .backspace => action = .CommandBackspace,
                        .enter => action = .ExecuteCommand,
                        else => {},
                    }
                },
            }
        }

        if (action) |a| {
            try dot.execute(a);
        }
        try dot.win.updateSize();
    }
    try terminal.closeAlternateScreen(stdout);
    // try stdout.writeAll("\x1b[H\x1b[2J\x1b[3J");
}
