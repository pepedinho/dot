const std = @import("std");
const buffer = @import("gap.zig");

pub const Mode = enum {
    Normal,
    Insert,
    Command,
};

pub const Action = union(enum) {
    InsertChar: u8,
    InsertNewLine,
    DeleteChar,
    MoveLeft,
    MoveRight,
    MoveUp,
    MoveDown,
    SetMode: Mode,
    Quit,
};

pub const Editor = struct {
    allocator: std.mem.Allocator,
    buf: buffer.GapBuffer,
    mode: Mode,
    is_running: bool,
    needs_redraw: bool,

    pub fn init(allocator: std.mem.Allocator) !Editor {
        return Editor{
            .allocator = allocator,
            .buf = try buffer.GapBuffer.init(allocator),
            .mode = .Normal,
            .is_running = true,
            .needs_redraw = true,
        };
    }

    pub fn deinit(self: *Editor) void {
        self.buf.deinit();
    }

    pub fn execute(self: *Editor, action: Action) !void {
        switch (action) {
            .SetMode => |m| {
                self.mode = m;
                self.needs_redraw = true;
            },
            .Quit => self.is_running = false,
            .InsertChar => |c| {
                try self.buf.insertChar(c);
                self.needs_redraw = false;
            },
            .InsertNewLine => {
                self.buf.insertChar('\n');
                self.needs_redraw = true;
            },
            .DeleteChar => {
                self.buf.backspace();
                self.needs_redraw = true;
            },
            .MoveLeft => {
                self.buf.moveCursorLeft();
                self.needs_redraw = false;
            },
            .MoveRight => {
                self.buf.moveCursorRight();
                self.needs_redraw = false;
            },
            .MoveDown => {
                self.buf.moveCursorDown();
                self.needs_redraw = false;
            },
            .MoveUp => {
                self.buf.moveCursorUp();
                self.needs_redraw = false;
            },
        }
    }
};
