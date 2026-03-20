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
            try ui.refreshScreen(stdout, &dot.buf);
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
    }
    try stdout.writeAll("\x1b[2J\x1b[H");
}

//
// var dot = try DotEditor.init(allocator);
// defer dot.deinit();
//
// while (dot.is_running) {
//     // --- VUE ---
//     if (dot.needs_redraw) {
//         try ui.refreshScreen(stdout, &dot.buf);
//     } else {
//         try ui.updateCurrentLine(stdout, &dot.buf);
//     }
//     // TODO: Afficher le mode actuel dans un coin de l'écran (ex: "-- INSERT --")
//     try stdout_writer.flush();
//
//     // --- INPUT ---
//     const key = try keyboard.readKey();
//     if (key == .none) continue;
//
//     // --- MAPPING (Clavier -> API) ---
//     var action_to_execute: ?Action = null;
//
//     switch (dot.mode) {
//         .Normal => {
//             switch (key) {
//                 .ascii => |c| {
//                     if (c == 'i') action_to_execute = .{ .SetMode = .Insert };
//                     if (c == 'h') action_to_execute = .MoveLeft;
//                     if (c == 'j') action_to_execute = .MoveDown;
//                     if (c == 'k') action_to_execute = .MoveUp;
//                     if (c == 'l') action_to_execute = .MoveRight;
//                     if (c == 'x') action_to_execute = .DeleteChar;
//                 },
//                 .escape => {
//                     // Pour quitter temporairement sans faire de mode :q
//                     action_to_execute = .Quit;
//                 },
//                 else => {},
//             }
//         },
//         .Insert => {
//             switch (key) {
//                 .escape => action_to_execute = .{ .SetMode = .Normal },
//                 .ascii => |c| action_to_execute = .{ .InsertChar = c },
//                 .enter => action_to_execute = .InsertNewLine,
//                 .backspace => action_to_execute = .DeleteChar,
//                 .left => action_to_execute = .MoveLeft,
//                 .right => action_to_execute = .MoveRight,
//                 else => {},
//             }
//         },
//         .Command => {
//             // Pour plus tard, quand on tapera ":w" ou ":q"
//         }
//     }
//
//     // --- DISPATCH ---
//     if (action_to_execute) |action| {
//         try dot.execute(action);
//     }
// }
