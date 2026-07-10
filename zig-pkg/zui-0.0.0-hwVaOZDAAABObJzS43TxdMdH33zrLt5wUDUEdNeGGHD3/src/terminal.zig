//! The main Terminal interface.
//!
//! This module coordinates the double-buffering and the ANSI backend.
//! Users interact with this module to run the rendering loop.

const std = @import("std");
const buffer = @import("buffer.zig");
const Buffer = buffer.Buffer;
const Cell = buffer.Cell;
const ansi = @import("backend/ansi.zig");
const Rect = @import("layout.zig").Rect;

pub const Pos = struct {
    x: u16,
    y: u16,
};

pub const Frame = struct {
    const Self = @This();

    /// The frame-local allocator. All widgets should be allocated using this.
    /// It is cleared automatically at the end of the draw call.
    allocator: std.mem.Allocator,

    /// The memory grid where widgets draw themselves.
    buffer: *Buffer,

    /// Used to place cursor at the end of a frame.
    cursor_position: ?Pos = null,

    /// Return the full usable area of the terminal screen.
    pub fn size(self: Self) Rect {
        return Rect.init(0, 0, self.buffer.width, self.buffer.height);
    }

    pub fn setCursor(self: *Self, x: u16, y: u16) void {
        self.cursor_position = .{ .x = x, .y = y };
    }
};

pub const Terminal = struct {
    const Self = @This();

    /// The allocator used for long-lived terminal state (the buffers).
    allocator: std.mem.Allocator,

    /// The arena allocator used and reset every frame.
    frame_arena: std.heap.ArenaAllocator,

    /// What is currenly visible on the screen.
    current_buffer: Buffer,

    /// What the user is drawing for the next frame.
    next_buffer: Buffer,

    /// Standard output writer for ANSI codes.
    writer: *std.Io.Writer,

    /// Initializes the terminal backend and buffers.
    pub fn init(allocator: std.mem.Allocator, writer: *std.Io.Writer, width: u16, height: u16) !Self {
        const term = Self{
            .allocator = allocator,
            .frame_arena = std.heap.ArenaAllocator.init(allocator),
            .current_buffer = try Buffer.init(allocator, width, height),
            .next_buffer = try Buffer.init(allocator, width, height),
            .writer = writer,
        };

        // try ansi.writeEnterAlternateScreen(term.writer);
        // try ansi.writeHideCursor(term.writer);
        // try ansi.writeClearScreen(term.writer);

        return term;
    }

    /// Cleans up memory and restores the terminal to its original state.
    pub fn deinit(self: *Self) void {
        ansi.writeShowCursor(self.writer) catch {};
        ansi.writeLeaveAlternateScreen(self.writer) catch {};

        self.writer.flush() catch {};

        self.current_buffer.deinit(self.allocator);
        self.next_buffer.deinit(self.allocator);
        self.frame_arena.deinit();
    }

    /// The main draw loop. Takes a user-provided closure/function to render the UI.
    pub fn draw(self: *Self, ctx: anytype, comptime renderFn: fn (@TypeOf(ctx), *Frame) void) !void {
        _ = self.frame_arena.reset(.retain_capacity);
        self.next_buffer.reset();

        var frame = Frame{
            .allocator = self.frame_arena.allocator(),
            .buffer = &self.next_buffer,
        };

        renderFn(ctx, &frame);

        try self.flush(frame.cursor_position);
    }

    /// The diffing engine: compares next_buffer with current_buffer an prints ANSI codes.
    fn flush(self: *Self, cursor: ?Pos) !void {
        var cursor_x: ?u16 = null;
        var cursor_y: ?u16 = null;
        var current_style: ?@import("style.zig").Style = null;

        var y: u16 = 0;
        while (y < self.next_buffer.height) : (y += 1) {
            var x: u16 = 0;
            while (x < self.next_buffer.width) : (x += 1) {
                const next_cell = self.next_buffer.get(x, y) orelse continue;
                const curr_cell = self.current_buffer.get(x, y) orelse continue;

                const symbol_changed = !std.mem.eql(u8, next_cell.getSymbol(), curr_cell.getSymbol());
                const stye_changed = !std.meta.eql(next_cell.style, curr_cell.style);

                if (symbol_changed or stye_changed) {
                    if (cursor_x == null or cursor_y == null or cursor_x.? != x or cursor_y.? != y) {
                        try ansi.writeMoveCursor(self.writer, x, y);
                    }

                    if (current_style == null or !std.meta.eql(current_style.?, next_cell.style)) {
                        try ansi.writeResetStyle(self.writer);
                        if (next_cell.style.fg) |fg| try ansi.writeFg(self.writer, fg);
                        if (next_cell.style.bg) |bg| try ansi.writeBg(self.writer, bg);

                        try ansi.writeModifiers(self.writer, next_cell.style.add_modifier);

                        current_style = next_cell.style;
                    }

                    _ = try self.writer.write(next_cell.getSymbol());

                    cursor_x = x + 1;
                    cursor_y = y;
                }
            }
        }

        if (cursor) |pos| {
            try ansi.writeMoveCursor(self.writer, pos.x, pos.y);
            try ansi.writeShowCursor(self.writer);
        } else {
            try ansi.writeHideCursor(self.writer);
        }

        try self.writer.flush();
        std.mem.swap(Buffer, &self.current_buffer, &self.next_buffer);
    }
};
