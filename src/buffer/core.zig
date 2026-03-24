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
    CommandChar: u8,
    CommandBackspace,
    ExecuteCommand,
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
        var ws = std.posix.winsize{
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

const MAX_FILE_SIZE: usize = 10 * 1024 * 1024; // 10 MB

pub const Editor = struct {
    allocator: std.mem.Allocator,
    buf: buffer.GapBuffer,
    mode: Mode,
    is_running: bool,
    needs_redraw: bool,
    win: Window,
    cmd_buf: std.ArrayList(u8),
    filename: ?[]u8,

    pub fn init(allocator: std.mem.Allocator) !Editor {
        return Editor{
            .allocator = allocator,
            .buf = try buffer.GapBuffer.init(allocator),
            .mode = .Normal,
            .is_running = true,
            .needs_redraw = true,
            .win = try Window.init(),
            .cmd_buf = std.ArrayList(u8).init(allocator),
            .filename = null,
        };
    }

    pub fn deinit(self: *Editor) void {
        self.buf.deinit();
        self.cmd_buf.deinit();
        if (self.filename) |f| self.allocator.free(f);
    }

    pub fn loadFile(self: *Editor, path: []const u8) !void {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, MAX_FILE_SIZE);
        defer self.allocator.free(content);

        self.buf.deinit();
        self.buf = try buffer.GapBuffer.init(self.allocator);

        for (content) |c| {
            try self.buf.insertChar(c);
        }

        while (self.buf.gap_start > 0) {
            self.buf.moveCursorLeft();
        }

        if (self.filename) |f| self.allocator.free(f);
        self.filename = try self.allocator.dupe(u8, path);
        self.needs_redraw = true;
    }

    pub fn saveFile(self: *Editor, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        try file.writeAll(self.buf.getFirst());
        try file.writeAll(self.buf.getSecond());
    }

    fn executeCommand(self: *Editor) !void {
        const cmd = self.cmd_buf.items;

        if (std.mem.eql(u8, cmd, "q")) {
            self.is_running = false;
        } else if (std.mem.eql(u8, cmd, "w")) {
            if (self.filename) |path| {
                try self.saveFile(path);
            }
        } else if (std.mem.eql(u8, cmd, "wq")) {
            if (self.filename) |path| {
                try self.saveFile(path);
                self.is_running = false;
            }
        } else if (std.mem.startsWith(u8, cmd, "w ") and cmd.len > 2) {
            const path = cmd[2..];
            try self.saveFile(path);
            if (self.filename) |f| self.allocator.free(f);
            self.filename = try self.allocator.dupe(u8, path);
        } else if (std.mem.startsWith(u8, cmd, "e ") and cmd.len > 2) {
            const path = cmd[2..];
            try self.loadFile(path);
        }
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
            .CommandChar => |c| {
                try self.cmd_buf.append(c);
                self.needs_redraw = true;
            },
            .CommandBackspace => {
                _ = self.cmd_buf.popOrNull();
                self.needs_redraw = true;
            },
            .ExecuteCommand => {
                try self.executeCommand();
                self.cmd_buf.clearRetainingCapacity();
                self.mode = .Normal;
                self.needs_redraw = true;
            },
        }
    }
};
