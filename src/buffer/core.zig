const std = @import("std");
const buffer = @import("gap.zig");
const pop = @import("../view/pop.zig");
const utils = @import("../utils.zig");
const keybinds = @import("keybinds.zig");
const ui = @import("../view/ui.zig");
const keyboard = @import("../view/keyboard.zig");
const pane = @import("pane.zig");
const fs = @import("../fs/filesystem.zig");

pub const CoreError = error{
    NoFileName,
    QueueFull,
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
    UpdateDebugBuffer: *buffer.GapBuffer,
    // SplitView,
    // GotoView: u8,
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

pub const ActionQueue = struct {
    buffer: [256]Action = undefined,
    head: usize = 0,
    tail: usize = 0,

    pub fn push(self: *ActionQueue, action: Action) CoreError!void {
        const next_head = (self.head + 1) % self.buffer.len;
        if (next_head == self.tail)
            return CoreError.QueueFull;
        self.buffer[self.head] = action;
        self.head = next_head;
    }

    pub fn pop(self: *ActionQueue) ?Action {
        if (self.head == self.tail) return null; // empty queue

        const action = self.buffer[self.tail];
        self.tail = (self.tail + 1) % self.buffer.len;
        return action;
    }
};

pub const Job = struct {
    action: Action,
    interval_ms: i64,
    last_run: i64,
};

pub const Scheduler = struct {
    jobs: [32]?Job = .{null} ** 32,

    pub fn add(self: *Scheduler, action: Action, interval_ms: i64) !void {
        const now = std.time.milliTimestamp();
        for (&self.jobs) |*slot| {
            if (slot.* == null) {
                slot.* = .{
                    .action = action,
                    .interval_ms = interval_ms,
                    .last_run = now,
                };
                return;
            }
        }
        return error.SchedulerFull;
    }

    pub fn update(self: *Scheduler, queue: *ActionQueue) !void {
        const now = std.time.milliTimestamp();
        for (&self.jobs) |*slot| {
            if (slot.*) |*job| {
                if (now - job.last_run >= job.interval_ms) {
                    try queue.push(job.action);
                    job.last_run = now;
                }
            }
        }
    }
};

pub const Editor = struct {
    allocator: std.mem.Allocator,
    buffers: std.ArrayList(*buffer.GapBuffer),
    views: std.ArrayList(pane.View),
    active_view_idx: usize = 0,
    mode: Mode,
    last_mode: Mode,
    is_running: bool,
    needs_redraw: bool,
    is_dirty: bool = true,
    win: Window,
    cmd_buf: std.ArrayListUnmanaged(u8),
    filename: ?[]const u8,
    pop_store: std.AutoHashMap(u32, pop.Pop),
    next_popup_id: u32 = 1,
    key_binds: std.AutoHashMap(u8, Action),
    action_queue: ActionQueue = .{},
    scheduler: Scheduler = .{},
    debug_view_idx: ?usize = null,

    pub fn init(allocator: std.mem.Allocator) !Editor {
        var ed = Editor{
            .allocator = allocator,
            .buffers = .empty,
            .mode = .Normal,
            .last_mode = .Normal,
            .is_running = true,
            .needs_redraw = true,
            .win = try Window.init(),
            .cmd_buf = .empty,
            .filename = null,
            .pop_store = std.AutoHashMap(u32, pop.Pop).init(allocator),
            .key_binds = std.AutoHashMap(u8, Action).init(allocator),
            .views = .empty,
        };

        const main_buf = try allocator.create(buffer.GapBuffer);
        main_buf.* = try buffer.GapBuffer.init(allocator);
        try ed.buffers.append(allocator, main_buf);

        try ed.views.append(ed.allocator, pane.View{
            .x = 1,
            .y = 1,
            .width = ed.win.cols,
            .height = if (ed.win.rows > 0) ed.win.rows - 1 else 0,
            .buf = main_buf,
        });

        try ed.scheduler.add(.Tick, 33);
        return ed;
    }

    pub fn getActiveView(self: *Editor) *pane.View {
        return &self.views.items[self.active_view_idx];
    }

    pub fn loadStandardKeyBinds(self: *Editor) !void {
        try keybinds.loadStandardKeyBinds(self);
    }

    pub fn deinit(self: *Editor) void {
        var it = self.pop_store.valueIterator();
        while (it.next()) |v| {
            v.deinit();
        }
        for (self.buffers.items) |b| {
            b.deinit();
            self.allocator.destroy(b);
        }
        self.buffers.deinit(self.allocator);
        self.pop_store.deinit();
        self.key_binds.deinit();
        self.cmd_buf.deinit(self.allocator);
        self.views.deinit(self.allocator);
    }

    pub fn pushAction(self: *Editor, action: Action) !void {
        try self.action_queue.push(action);
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
        const view = self.getActiveView();
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
                    self.is_dirty = true;
                }
                try self.updateDebugPanel();
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
                if (view.is_readonly) return;
                try view.buf.insertChar(c);
                self.needs_redraw = false;
            },
            .InsertNewLine => {
                if (view.is_readonly) return;
                try view.buf.insertChar('\n');
                self.needs_redraw = true;
            },
            .DeleteChar => {
                if (view.is_readonly) return;
                const delete_nl = view.buf.gap_start > 0 and view.buf.buffer[view.buf.gap_start - 1] == '\n';
                view.buf.backspace();
                self.needs_redraw = delete_nl;
            },
            .MoveLeft => {
                view.buf.moveCursorLeft();
                self.needs_redraw = false;
            },
            .MoveRight => {
                view.buf.moveCursorRight();
                self.needs_redraw = false;
            },
            .MoveDown => {
                view.buf.moveCursorDown();
                self.needs_redraw = false;
            },
            .MoveUp => {
                view.buf.moveCursorUp();
                self.needs_redraw = false;
            },
            .Append => {
                if (view.is_readonly) return;
                try self.pushAction(.MoveRight);
                try self.pushAction(.{ .SetMode = .Insert });
            },
            .AppendNewLine => {
                if (view.is_readonly) return;
                try self.pushAction(.MoveDown);
                try self.pushAction(.{ .SetMode = .Insert });
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
                self.needs_redraw = true;
            },
            .ClearCommandBuf => {
                self.cmd_buf.clearRetainingCapacity();
            },
        }
    }

    fn getCurrentBufferIdx(self: *Editor) usize {
        const view = self.getActiveView();

        var current_buffer_idx: usize = 0;
        for (self.buffers.items, 0..) |b, i| {
            if (b == view.buf) {
                current_buffer_idx = i;
                break;
            }
        }
        return current_buffer_idx;
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

        const view = self.getActiveView();

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
            view.buf.jumpTo(.{ .x = 1, .y = 1 });
        } else if (std.mem.eql(u8, cmd, "file")) {
            self.loadFile(args);
        } else if (std.mem.eql(u8, cmd, "split")) {
            const buf = try self.allocator.create(buffer.GapBuffer);
            buf.* = try buffer.GapBuffer.init(self.allocator);
            try self.buffers.append(self.allocator, buf);
            try self.splitHorizontal(buf);
        } else if (std.mem.eql(u8, cmd, "vsplit")) {
            const buf = try self.allocator.create(buffer.GapBuffer);
            buf.* = try buffer.GapBuffer.init(self.allocator);
            try self.buffers.append(self.allocator, buf);
            try self.splitVertical(buf);
        } else if (std.mem.eql(u8, cmd, "goto") and utils.isDigitSlice(args)) {
            const idx = try std.fmt.parseInt(usize, args, 10);
            self.switchView(idx);
        } else if (std.mem.eql(u8, cmd, "open")) {
            const content = try fs.Fs.loadFast(self.allocator, args);
            defer self.allocator.free(content);
            const new_buf = try self.allocator.create(buffer.GapBuffer);
            new_buf.* = try buffer.GapBuffer.initFromFile(self.allocator, content);

            try self.buffers.append(self.allocator, new_buf);
            view.buf = new_buf;
            view.col_offset = 0;
            view.row_offset = 0;
            self.filename = args; // need to be reworked
            self.needs_redraw = true;
        } else if (std.mem.eql(u8, cmd, "bprev")) {
            if (self.buffers.items.len <= 1) return;

            const current_buffer_idx = self.getCurrentBufferIdx();

            const prev_idx = if (current_buffer_idx == 0)
                self.buffers.items.len - 1
            else
                current_buffer_idx - 1;

            view.buf = self.buffers.items[prev_idx];
            view.col_offset = 0;
            view.row_offset = 0;
            self.needs_redraw = true;
        } else if (std.mem.eql(u8, cmd, "bnext")) {
            if (self.buffers.items.len <= 1) return;
            const current_buffer_idx = self.getCurrentBufferIdx();

            const next_idx = (current_buffer_idx + 1) % self.buffers.items.len;

            view.buf = self.buffers.items[next_idx];
            view.col_offset = 0;
            view.row_offset = 0;
            self.needs_redraw = true;
        } else if (std.mem.eql(u8, cmd, "debug")) {
            if (self.debug_view_idx == null) {
                const buf = try self.allocator.create(buffer.GapBuffer);
                buf.* = try buffer.GapBuffer.init(self.allocator);
                try self.buffers.append(self.allocator, buf);

                try self.splitVertical(buf);

                const new_idx = self.views.items.len - 1;
                self.views.items[new_idx].is_readonly = true;
                self.debug_view_idx = new_idx;
                self.needs_redraw = true;
            }
        } else if (utils.isDigitSlice(cmd)) {
            const l = try std.fmt.parseInt(usize, self.cmd_buf.items, 10);
            view.buf.jumpTo(.{ .x = 1, .y = l });
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
        const view = self.getActiveView();

        const file = if (std.fs.path.isAbsolute(name))
            try std.fs.createFileAbsolute(name, .{})
        else
            try std.fs.cwd().createFile(name, .{});
        defer file.close();

        try file.writeAll(view.buf.getFirst());
        try file.writeAll(view.buf.getSecond());
    }

    pub fn splitHorizontal(self: *Editor, target_buf: *buffer.GapBuffer) !void {
        const active_idx = self.active_view_idx;

        const current_height = self.views.items[active_idx].height;
        if (current_height < 3) return;
        const half_height = current_height / 2;

        const remaining_height = current_height - half_height - 1;

        self.views.items[active_idx].height = half_height;

        const new_view = pane.View{
            .x = self.views.items[active_idx].x,
            .y = self.views.items[active_idx].y + @as(u16, @intCast(half_height + 1)),
            .width = self.views.items[active_idx].width,
            .height = remaining_height,
            .buf = target_buf,
            .row_offset = 0,
            .col_offset = 0,
        };

        try self.views.append(self.allocator, new_view);
        self.active_view_idx = self.views.items.len - 1;
        self.needs_redraw = true;
    }

    pub fn splitVertical(self: *Editor, target_buf: *buffer.GapBuffer) !void {
        const active_idx = self.active_view_idx;

        const current_width = self.views.items[active_idx].width;
        if (current_width < 5) return;

        const half_width = current_width / 2;
        const remaining_width = current_width - half_width - 1;
        self.views.items[active_idx].width = half_width;

        const new_view = pane.View{
            .x = self.views.items[active_idx].x + @as(u16, @intCast(half_width)) + 1,
            .y = self.views.items[active_idx].y, // Le Y ne change pas
            .width = remaining_width,
            .height = self.views.items[active_idx].height,
            .buf = target_buf,
            .row_offset = 0,
            .col_offset = 0,
        };

        try self.views.append(self.allocator, new_view);
        self.active_view_idx = self.views.items.len - 1;
        self.needs_redraw = true;
    }

    fn switchView(self: *Editor, idx: usize) void {
        if (idx < self.views.items.len) {
            self.active_view_idx = idx;
            self.needs_redraw = true;
        }
    }

    pub fn run(self: *Editor, stdout: *std.Io.Writer) !void {
        while (self.is_running) {
            if (self.is_dirty) {
                var active = self.getActiveView();

                if (active.scroll()) {
                    self.needs_redraw = true;
                }

                if (self.needs_redraw) {
                    try ui.refreshScreen(stdout, self);
                    self.needs_redraw = false;
                } else {
                    try ui.updateCurrentLine(stdout, self);
                }
                self.is_dirty = false;
            }

            try stdout.flush();

            const key = try keyboard.readKey();
            try self.scheduler.update(&self.action_queue);

            if (key != .none) {
                self.is_dirty = true;
                switch (self.mode) {
                    .Normal => {
                        switch (key) {
                            .ascii => |c| {
                                if (self.key_binds.get(c)) |a| {
                                    try self.pushAction(a);
                                }
                            },
                            .left => try self.pushAction(.MoveLeft),
                            .right => try self.pushAction(.MoveRight),
                            .down => try self.pushAction(.MoveDown),
                            .up => try self.pushAction(.MoveUp),
                            else => {},
                        }
                    },
                    .Insert => {
                        switch (key) {
                            .escape => try self.pushAction(.{ .SetMode = .Normal }),
                            .ascii => |c| try self.pushAction(.{ .InsertChar = c }),
                            .enter => try self.pushAction(.InsertNewLine),
                            .backspace => try self.pushAction(.DeleteChar),
                            .left => try self.pushAction(.MoveLeft),
                            .right => try self.pushAction(.MoveRight),
                            .up => try self.pushAction(.MoveUp),
                            .down => try self.pushAction(.MoveDown),
                            else => {},
                        }
                    },
                    .Command => {
                        switch (key) {
                            .escape => try self.pushAction(.{ .SetMode = .Normal }),
                            .ascii => |c| {
                                try self.pushAction(.{ .CommandChar = c });
                            },
                            .backspace => try self.pushAction(.CommandBackspace),
                            .enter => try self.pushAction(.ExecuteCommand),
                            else => {},
                        }
                    },
                }
            }

            while (self.action_queue.pop()) |act| {
                try self.execute(act);
            }
            try self.win.updateSize();
            std.Thread.sleep(16_000_000);
        }
    }

    fn updateDebugPanel(self: *Editor) !void {
        if (self.debug_view_idx) |idx| {
            const debug_buf = self.views.items[idx].buf;

            debug_buf.gap_start = 0;
            debug_buf.gap_end = debug_buf.buffer.len;

            var fmt_buf: [1024]u8 = undefined;

            const text = try std.fmt.bufPrint(&fmt_buf, "=== DEBUG PANEL ===\n\n" ++
                "Buffers ouverts : {d}\n" ++
                "Vues actives    : {d}\n" ++
                "Vue courante    : {d}\n\n", .{
                self.buffers.items.len,
                self.views.items.len,
                self.active_view_idx,
            });

            for (text) |c| {
                try debug_buf.insertChar(c);
            }
        }
    }
};
