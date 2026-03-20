const std = @import("std");
const buffer = @import("buffer/gap.zig");
const terminal = @import("view/terminal.zig");
const keyboard = @import("view/keyboard.zig");
const ui = @import("view/ui.zig");

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

    var buf = try buffer.GapBuffer.init(allocator);
    defer buf.deinit();

    var stoudt_buf: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stoudt_buf);
    const stdout = &stdout_writer.interface;
    try ui.refreshScreen(stdout, &buf);
    try stdout.flush();

    var need_full_redraw = false;

    while (true) {
        try stdout.flush();
        const key = try keyboard.readKey();
        switch (key) {
            .none => continue, // Timeout, on boucle
            .escape => {
                // Pour l'instant, Echap quitte l'éditeur
                break;
            },
            .left => {
                buf.moveCursorLeft();
                need_full_redraw = true;
            },
            .right => {
                buf.moveCursorRight();
                need_full_redraw = false;
            },
            .up => {
                buf.moveCursorUp();
                // TODO : Calculer l'index de la ligne du dessus
            },
            .down => {
                buf.moveCursorDown();
                // TODO : Calculer l'index de la ligne du dessous
            },
            .backspace => {
                const pos = buf.getCursorPos();
                if (pos.x == 1) {
                    need_full_redraw = true;
                } else {
                    need_full_redraw = false;
                }
                buf.backspace();
            },
            .enter => {
                try buf.insertChar('\n');
                need_full_redraw = true;
            },
            .ascii => |c| {
                try buf.insertChar(c);
                need_full_redraw = false;
            },
        }

        if (need_full_redraw) {
            try ui.refreshScreen(stdout, &buf);
        } else {
            try ui.updateCurrentLine(stdout, &buf);
        }
        try stdout.flush();
    }

    try stdout.writeAll("\x1b[2J\x1b[H");

    // std.debug.print("gap_buf.len: {d}\n", .{gap_buf.gap_end});
    // std.debug.print("{any}", .{gap_buf.buffer});
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
