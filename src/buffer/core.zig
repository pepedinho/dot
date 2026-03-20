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
    Append,
    AppendNewLine,
    Quit,
};
const builtin = @import("builtin");

const TIOCGWINSZ = if (builtin.os.tag == .macos) 0x40087468 else 0x5413;

pub const Window = struct {
    rows: u16,
    cols: u16,

    pub fn init() !Window {
        var win = Window{ .rows = 0, .cols = 0 };
        try win.updateSize();
        return win;
    }

    pub fn updateSize(self: *Window) !void {
        var ws = std.posix.system.winsize{
            .row = 0,
            .col = 0,
            .xpixel = 0,
            .ypixel = 0,
        };

        const err = std.posix.system.ioctl(std.posix.STDOUT_FILENO, TIOCGWINSZ, @intFromPtr(&ws));
        if (err == -1) return error.IoctlError;

        self.cols = ws.col;
        self.rows = ws.row;
    }
};

pub const Editor = struct {
    allocator: std.mem.Allocator,
    buf: buffer.GapBuffer,
    mode: Mode,
    is_running: bool,
    needs_redraw: bool,
    win: Window,

    pub fn init(allocator: std.mem.Allocator) !Editor {
        return Editor{
            .allocator = allocator,
            .buf = try buffer.GapBuffer.init(allocator),
            .mode = .Normal,
            .is_running = true,
            .needs_redraw = true,
            .win = try Window.init(),
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
                try self.buf.insertChar('\n');
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
            .Append => {
                self.buf.moveCursorRight();
                self.mode = .Insert;
                self.needs_redraw = true;
            },
            .AppendNewLine => {
                self.buf.moveCursorDown();
                self.mode = .Insert;
                self.needs_redraw = true;
            },
        }
    }
};
