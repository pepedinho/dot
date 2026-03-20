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

    // try buf.insertChar('S');
    // try buf.insertChar('a');
    // try buf.insertChar('l');
    // try buf.insertChar('u');
    // try buf.insertChar('t');
    // buf.printDebug();
    //
    // buf.moveCursorLeft();
    // buf.moveCursorLeft();
    // std.debug.print("move left\n", .{});
    //
    // try buf.insertChar('o');
    // try buf.insertChar('p');
    // std.debug.print("insert in middle\n", .{});
    // buf.printDebug();
    //
    // buf.backspace();
    // std.debug.print("backspace\n", .{});
    // buf.printDebug();
    //
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
                // TODO : Calculer l'index de la ligne du dessus
            },
            .down => {
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
