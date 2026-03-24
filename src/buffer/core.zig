const std = @import("std");
const buffer = @import("gap.zig");
const pop = @import("../view/pop.zig");
const utils = @import("../utils.zig");

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
    is_running: bool,
    needs_redraw: bool,
    win: Window,
    pop_store: std.AutoHashMap(u32, pop.Pop),
    next_popup_id: u32 = 1,

    pub fn init(allocator: std.mem.Allocator) !Editor {
        return Editor{
            .allocator = allocator,
            .buf = try buffer.GapBuffer.init(allocator),
            .mode = .Normal,
            .is_running = true,
            .needs_redraw = true,
            .win = try Window.init(),
            .pop_store = std.AutoHashMap(u32, pop.Pop).init(allocator),
        };
    }

    pub fn deinit(self: *Editor) void {
        self.buf.deinit();

        var it = self.pop_store.valueIterator();
        while (it.next()) |v| {
            v.deinit();
        }
        self.pop_store.deinit();
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
            .CreatePop => |b| {
                const pop_id = try self.createPop(b.pos, b.size, b.duration_ms);
                if (self.pop_store.getPtr(pop_id)) |popup| {
                    try popup.write(b.text);
                }
                self.needs_redraw = true;
            },
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
        const cursor_pos = self.buf.getCursorPos();
        var it = self.pop_store.valueIterator();
        while (it.next()) |entry| {
            try pop.render(out, entry);
        }
        try out.print("\x1b[{d};{d}H", .{ cursor_pos.y, cursor_pos.x });
    }
};
