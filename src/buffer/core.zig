const std = @import("std");
const buffer = @import("gap.zig");
const pop = @import("../view/pop.zig");
const utils = @import("../utils.zig");
const keybinds = @import("keybinds.zig");

pub const CoreError = error{
    NoFileName,
};

pub const Mode = enum {
    Normal,
    Insert,
    Command,
};

pub const PopBuilder = struct {
    size: utils.Pos,
    pos: utils.Pos,
    text: []const u8,
    duration_ms: ?i64,
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
    CreatePop: PopBuilder,
    CommandChar: u8,
    CommandBackspace,
    ExecuteCommand,
    ClearCommandBuf,
    Quit,
    Tick,
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

pub const Editor = struct {
    allocator: std.mem.Allocator,
    buf: buffer.GapBuffer,
    mode: Mode,
    last_mode: Mode,
    is_running: bool,
    needs_redraw: bool,
    row_offset: usize = 0,
    col_offset: usize = 0,
    win: Window,
    cmd_buf: std.ArrayListUnmanaged(u8),
    filename: ?[]const u8,
    pop_store: std.AutoHashMap(u32, pop.Pop),
    next_popup_id: u32 = 1,
    key_binds: std.AutoHashMap(u8, Action),

    pub fn init(allocator: std.mem.Allocator) !Editor {
        return Editor{
            .allocator = allocator,
            .buf = try buffer.GapBuffer.init(allocator),
            .mode = .Normal,
            .last_mode = .Normal,
            .is_running = true,
            .needs_redraw = true,
            .win = try Window.init(),
            .cmd_buf = .empty,
            .filename = null,
            .pop_store = std.AutoHashMap(u32, pop.Pop).init(allocator),
            .key_binds = std.AutoHashMap(u8, Action).init(allocator),
        };
    }

    pub fn loadStandardKeyBinds(self: *Editor) !void {
        try keybinds.loadStandardKeyBinds(self);
    }

    pub fn deinit(self: *Editor) void {
        self.buf.deinit();

        var it = self.pop_store.valueIterator();
        while (it.next()) |v| {
            v.deinit();
        }
        self.pop_store.deinit();
        self.key_binds.deinit();
        self.cmd_buf.deinit(self.allocator);
    }

    pub fn loadFile(self: *Editor, filename: []const u8) void {
        self.filename = filename;
    }

    pub fn quit(self: *Editor) void {
        self.is_running = false;
    }

    pub fn registerKeyBind(self: *Editor, key: u8, action: Action) !void {
        try self.key_binds.put(key, action);
    }

    pub fn execute(self: *Editor, action: Action) !void {
        switch (action) {
            .Tick => {
                const now = std.time.milliTimestamp();
                var it = self.pop_store.iterator();
                var to_remove: std.ArrayList(u32) = .empty;
                defer to_remove.deinit(self.allocator);

                while (it.next()) |entry| {
                    if (entry.value_ptr.expire_at) |expiration| {
                        if (now >= expiration) {
                            try to_remove.append(self.allocator, entry.key_ptr.*);
                        }
                    }
                }

                for (to_remove.items) |id| {
                    self.destroyPop(id);
                    self.needs_redraw = true;
                }
            },
            .SetMode => |m| {
                self.last_mode = self.mode;
                if (self.mode == .Command) {
                    self.cmd_buf.clearRetainingCapacity();
                }
                self.mode = m;
                self.needs_redraw = true;
            },
            .Quit => self.quit(),
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
                self.needs_redraw = true;
            },
            .MoveRight => {
                self.buf.moveCursorRight();
                self.needs_redraw = true;
            },
            .MoveDown => {
                self.buf.moveCursorDown();
                self.needs_redraw = true;
            },
            .MoveUp => {
                self.buf.moveCursorUp();
                self.needs_redraw = true;
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
            .CreatePop => |b| {
                const pop_id = try self.createPop(b.pos, b.size, b.duration_ms);
                if (self.pop_store.getPtr(pop_id)) |popup| {
                    try popup.write(b.text);
                }
                self.needs_redraw = true;
            },
            .CommandChar => |c| {
                try self.cmd_buf.append(self.allocator, c);
                self.needs_redraw = true;
            },
            .CommandBackspace => {
                _ = self.cmd_buf.pop();
                self.needs_redraw = true;
            },
            .ExecuteCommand => {
                try self.executeCmd();
            },
            .ClearCommandBuf => {
                self.cmd_buf.clearRetainingCapacity();
            },
        }
    }

    pub fn registerPop(self: *Editor, pos: ?utils.Pos, size: ?utils.Pos, text: []const u8, duration: ?u32) !void {
        const w_s = self.win;
        const popup = PopBuilder{
            .pos = pos orelse .{ .x = w_s.cols / 2, .y = w_s.rows / 2 },
            .size = size orelse .{ .x = text.len + 4, .y = 3 },
            .text = text,
            .duration_ms = duration orelse 2000,
        };
        const pop_id = try self.createPop(popup.pos, popup.size, popup.duration_ms);
        if (self.pop_store.getPtr(pop_id)) |p| {
            try p.write(popup.text);
        }
        self.needs_redraw = true;
    }

    fn executeCmd(self: *Editor) !void {
        defer {
            self.mode = self.last_mode;
            self.cmd_buf.clearRetainingCapacity();
        }

        const input = std.mem.trim(u8, self.cmd_buf.items, " \t");
        if (input.len == 0) return;

        const space_index = std.mem.indexOfScalar(u8, input, ' ');

        const cmd = if (space_index) |idx| self.cmd_buf.items[0..idx] else input;
        const args = if (space_index) |idx| std.mem.trim(u8, input[idx..], " \t") else "";

        if (std.mem.eql(u8, cmd, "q")) {
            self.quit();
        } else if (std.mem.eql(u8, cmd, "w")) {
            try self.saveFile();
            if (self.filename) |filename|
                try self.registerPop(null, null, filename, null);
        } else if (std.mem.eql(u8, cmd, "wq")) {
            try self.saveFile();
            self.quit();
        } else if (std.mem.eql(u8, cmd, "top")) {
            self.buf.jumpTo(.{ .x = 1, .y = 1 });
        } else if (std.mem.eql(u8, cmd, "file")) {
            self.loadFile(args);
        } else if (utils.isDigitSlice(cmd)) {
            const l = try std.fmt.parseInt(usize, self.cmd_buf.items, 10);
            self.buf.jumpTo(.{ .x = 1, .y = l });
        }
    }

    pub fn createPop(self: *Editor, pos: utils.Pos, size: utils.Pos, duration_ms: ?i64) !u32 {
        const id = self.next_popup_id;
        self.next_popup_id += 1;
        const popup = pop.Pop.init(self.allocator, id, pos, size, duration_ms);
        try self.pop_store.put(id, popup);

        return id;
    }

    pub fn destroyPop(self: *Editor, id: u32) void {
        if (self.pop_store.fetchRemove(id)) |kv| {
            var popup = kv.value;
            popup.deinit();
        }
    }

    pub fn renderAllPopup(
        self: *Editor,
        out: *std.Io.Writer,
    ) !void {
        // const cursor_pos = self.buf.getCursorPos();
        var it = self.pop_store.valueIterator();
        while (it.next()) |entry| {
            try pop.render(out, entry);
        }
        // try out.print("\x1b[{d};{d}H", .{ cursor_pos.y, cursor_pos.x });
    }

    pub fn saveFile(self: *Editor) !void {
        const name = self.filename orelse {
            return try self.registerPop(null, null, "No file name", 3000);
        };

        const file = if (std.fs.path.isAbsolute(name))
            try std.fs.createFileAbsolute(name, .{})
        else
            try std.fs.cwd().createFile(name, .{});
        defer file.close();

        try file.writeAll(self.buf.getFirst());
        try file.writeAll(self.buf.getSecond());
    }

    pub fn scroll(self: *Editor) void {
        const pos = self.buf.getCursorPos();

        if (pos.y <= self.row_offset) {
            self.row_offset = pos.y - 1;
        }

        if (pos.y >= self.row_offset + self.win.rows) {
            self.row_offset = pos.y - self.win.rows + 1;
        }

        if (pos.x <= self.col_offset) {
            self.col_offset = pos.x - 1;
        }
        if (pos.x >= self.col_offset + self.win.cols) {
            self.col_offset = pos.x - self.win.cols + 1;
        }
    }
};
