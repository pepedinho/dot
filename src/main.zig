const std = @import("std");
const buffer = @import("buffer/gap.zig");
const terminal = @import("view/terminal.zig");
const keyboard = @import("view/keyboard.zig");
const ui = @import("view/ui.zig");
const Editor = @import("buffer/core.zig").Editor;
const Action = @import("buffer/core.zig").Action;

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

    var dot = try Editor.init(allocator);
    defer dot.deinit();

    while (dot.is_running) {
        if (dot.needs_redraw) {
            try ui.refreshScreen(stdout, &dot);
        } else {
            try ui.updateCurrentLine(stdout, &dot.buf);
        }

        try stdout.flush();

        const key = try keyboard.readKey();
        // if (key == .none) continue;

        var action: ?Action = null;
        // std.debug.print("{any}", .{key});

        switch (dot.mode) {
            .Normal => {
                switch (key) {
                    .ascii => |c| {
                        if (c == 'i') action = .{ .SetMode = .Insert };
                        if (c == 'h') action = .MoveLeft;
                        if (c == 'j') action = .MoveDown;
                        if (c == 'k') action = .MoveUp;
                        if (c == 'l') action = .MoveRight;
                        if (c == 'x') action = .DeleteChar;
                        if (c == 'q') action = .Quit;
                    },
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
                    else => {},
                }
            },
            .Command => {},
        }

        if (action) |a| {
            try dot.execute(a);
        }
        try dot.win.updateSize();
    }
    try stdout.writeAll("\x1b[2J\x1b[H");
}
