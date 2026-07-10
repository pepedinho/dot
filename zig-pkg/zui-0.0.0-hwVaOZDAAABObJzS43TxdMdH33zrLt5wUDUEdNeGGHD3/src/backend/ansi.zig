//! This module handles the translation of Zui primitives into ANSI escape sequences.
//!
//! It provides functions to format colors, modifiers, and cursor movements
//! to be written directly to a standard `std.io.Writer`.

const std = @import("std");
const style_mod = @import("../style.zig");
const Color = style_mod.Color;
const Modifier = style_mod.Modifier;

pub const ESC = "\x1b[";

// =======================
// ANSI CODE GENERATOR
// =======================

pub fn writeHideCursor(writer: anytype) !void {
    try writer.print("{s}?25l", .{ESC});
}

pub fn writeShowCursor(writer: anytype) !void {
    try writer.print("{s}?25h", .{ESC});
}

pub fn writeClearScreen(writer: anytype) !void {
    // 2J clears the entire screen. H moves cursor to home (0,0).
    try writer.print("{s}2J{s}H", .{ ESC, ESC });
}

pub fn writeEnterAlternateScreen(writer: anytype) !void {
    try writer.print("{s}?1049h", .{ESC});
}

pub fn writeLeaveAlternateScreen(writer: anytype) !void {
    try writer.print("{s}?1049l", .{ESC});
}

pub fn writeMoveCursor(writer: anytype, x: u16, y: u16) !void {
    // ANSI coordinates are 1-based, Zui internal are 0-based.
    try writer.print("{s}{d};{d}H", .{ ESC, y + 1, x + 1 });
}

pub fn writeResetStyle(writer: anytype) !void {
    try writer.print("{s}0m", .{ESC});
}

// ==========================
// FG/BG COLOR TRANSLATION
// ==========================

pub fn writeFg(writer: anytype, color: Color) !void {
    switch (color) {
        .Reset => try writer.print("{s}39m", .{ESC}),
        .Black => try writer.print("{s}30m", .{ESC}),
        .Red => try writer.print("{s}31m", .{ESC}),
        .Green => try writer.print("{s}32m", .{ESC}),
        .Yellow => try writer.print("{s}33m", .{ESC}),
        .Blue => try writer.print("{s}34m", .{ESC}),
        .Magenta => try writer.print("{s}35m", .{ESC}),
        .Cyan => try writer.print("{s}36m", .{ESC}),
        .White => try writer.print("{s}37m", .{ESC}),
        .ANSI => |idx| try writer.print("{s}38;5;{d}m", .{ ESC, idx }),
        .RGB => |rgb| try writer.print("{s}38;2;{d};{d};{d}m", .{ ESC, rgb.r, rgb.g, rgb.b }),
    }
}

pub fn writeBg(writer: anytype, color: Color) !void {
    switch (color) {
        .Reset => try writer.print("{s}49m", .{ESC}),
        .Black => try writer.print("{s}40m", .{ESC}),
        .Red => try writer.print("{s}41m", .{ESC}),
        .Green => try writer.print("{s}42m", .{ESC}),
        .Yellow => try writer.print("{s}43m", .{ESC}),
        .Blue => try writer.print("{s}44m", .{ESC}),
        .Magenta => try writer.print("{s}45m", .{ESC}),
        .Cyan => try writer.print("{s}46m", .{ESC}),
        .White => try writer.print("{s}47m", .{ESC}),
        .ANSI => |idx| try writer.print("{s}48;5;{d}m", .{ ESC, idx }),
        .RGB => |rgb| try writer.print("{s}48;2;{d};{d};{d}m", .{ ESC, rgb.r, rgb.g, rgb.b }),
    }
}

pub fn writeModifiers(writer: anytype, modifier: Modifier) !void {
    if (modifier.bold) try writer.print("{s}1m", .{ESC});
    if (modifier.dim) try writer.print("{s}2m", .{ESC});
    if (modifier.italic) try writer.print("{s}3m", .{ESC});
    if (modifier.underlined) try writer.print("{s}4m", .{ESC});
    if (modifier.slow_blink) try writer.print("{s}5m", .{ESC});
    if (modifier.rapid_blink) try writer.print("{s}6m", .{ESC});
    if (modifier.reversed) try writer.print("{s}7m", .{ESC});
    if (modifier.hidden) try writer.print("{s}8m", .{ESC});
    if (modifier.crossed_out) try writer.print("{s}9m", .{ESC});
}
