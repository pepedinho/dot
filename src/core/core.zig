//! Core module it contain `Editor` struct which is the interface to interact with the dot editor

const std = @import("std");
pub const buffer = @import("gap.zig");
const pop = @import("../view/pop.zig");
const utils = @import("../utils.zig");
const keybinds = @import("keybinds.zig");
const keyboard = @import("../view/keyboard.zig");
const pane = @import("pane.zig");
const fs = @import("../fs/filesystem.zig");
const actions = @import("action.zig");
const scheduler = @import("scheduler.zig");
const commands = @import("commands.zig");
const api = @import("../api/api.zig");
const job = @import("worker.zig");
const ansi = @import("../view/ansi.zig");

const Style = @import("../view/style.zig").Style;
const c = api.c;
const TSManager = @import("treesitter.zig").TSManager;
const PumManager = @import("../view/pum.zig").PumManager;
const ToastManager = @import("../view/toast.zig").ToastManager;
const Action = actions.Action;
const ActionQueue = actions.ActionQueue;
const Scheduler = scheduler.Scheduler;
const CommandsMap = commands.CommandsMap;
const Renderer = @import("../view/renderer.zig").Renderer;
const JobManager = job.JobManager;
const ServerManager = job.ServerManager;
const GhostManager = @import("../view/ghost.zig").GhostManager;

pub const CoreError = error{
    NoFileName,
    QueueFull,
};

pub const Mode = enum {
    Normal,
    Insert,
    Command,
    Search,
};

/// a utiliti structure to create a `Pop`
pub const PopBuilder = struct {
    size: utils.Pos,
    pos: utils.Pos,
    text: []const u8,
    duration_ms: ?i64,
};

const builtin = @import("builtin");

const TIOCGWINSZ = if (builtin.os.tag == .macos) 0x40087468 else 0x5413;

/// `Window` struct is used to represent the whole terminal window
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

/// Provide an API to interact with the editor
/// the role of this struct is to centralize all vital function of dot editor
pub const Editor = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    env: *std.process.Environ.Map,
    buffers: std.ArrayList(*buffer.GapBuffer),
    views: std.ArrayList(pane.View),
    active_view_idx: usize = 0,
    mode: Mode,
    /// This attribut is used like memory for temporary mode like `.Command`
    last_mode: Mode,
    is_running: bool,
    /// If this flag is true the editor will process a full redraw in the next frame
    needs_redraw: bool,
    /// Tell the rendering engine that something has change.
    /// The engine will then apply the apporiate rendering level based on the change
    is_dirty: bool = true,
    /// Used for store and follow the terminal window size
    win: Window,
    /// Store the command line input
    cmd_buf: std.ArrayListUnmanaged(u8),
    /// This is used to store `Pop`
    /// Is map to store multiple active Pops by their unique ID.
    /// With different lifetime and attributs
    pop_store: std.AutoHashMap(u32, pop.Pop),
    toast_manager: ToastManager,
    ghost_manager: GhostManager,
    /// Used to increment id for assign
    next_popup_id: u32 = 1,
    /// Store keybinds and theirs associated Action
    key_binds: std.EnumArray(Mode, std.StringHashMap(Action)),
    pending_keys: std.ArrayList(u8),
    /// Ring buffer to store up 256 `Action`
    action_queue: ActionQueue = .{},
    /// Used to assign reccurent action to scheduler
    scheduler: Scheduler,
    /// Render engine used to render text to screen
    renderer: Renderer,
    clipboard: ?[]u8,
    pum: PumManager,
    // ========================
    // Debug Part
    // ========================
    // TODO: create a dedicated struct
    debug_view_idx: ?usize = null,
    debug_buf_idx: ?usize = null,
    // For fps counter
    frame_rendered: usize = 0,
    last_fps: usize = 0,
    last_fps_time: i64 = 0,
    cmd_map: CommandsMap,
    // =======================
    // LUA VM
    // =======================
    /// Lua vm instance
    vm: ?*c.lua_State = null,
    /// hooks registry
    hooks: std.StringHashMap(std.ArrayList(c_int)),
    job_manager: JobManager,
    server_manager: ServerManager,
    // =======================
    // TREE SITTER
    // =======================
    ts_manager: TSManager,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, env: *std.process.Environ.Map) !Editor {
        var binds = std.EnumArray(Mode, std.StringHashMap(Action)).initUndefined();
        for (std.enums.values(Mode)) |m| {
            binds.set(m, std.StringHashMap(Action).init(allocator));
        }
        var ed = Editor{
            .allocator = allocator,
            .io = io,
            .env = env,
            .buffers = .empty,
            .mode = .Normal,
            .last_mode = .Normal,
            .is_running = true,
            .needs_redraw = true,
            .win = try Window.init(),
            .cmd_buf = .empty,
            .pop_store = std.AutoHashMap(u32, pop.Pop).init(allocator),
            .key_binds = binds,
            .pending_keys = .empty,
            .cmd_map = CommandsMap.init(allocator),
            .views = .empty,
            .last_fps_time = std.Io.Clock.now(.real, io).toMilliseconds(),
            .renderer = Renderer.init(allocator),
            .clipboard = null,
            .toast_manager = ToastManager.init(allocator, io),
            .ghost_manager = GhostManager.init(allocator),
            .pum = PumManager.init(allocator),
            .hooks = std.StringHashMap(std.ArrayList(c_int)).init(allocator),
            .job_manager = JobManager.init(allocator, io),
            .server_manager = ServerManager.init(allocator, io),
            .ts_manager = try TSManager.init(allocator),
            .scheduler = .{ .io = io },
        };

        const main_buf = try allocator.create(buffer.GapBuffer);
        main_buf.* = try buffer.GapBuffer.init(allocator, io);
        try ed.buffers.append(allocator, main_buf);
        try ed.views.append(ed.allocator, pane.View{
            .x = 1,
            .y = 1,
            .width = ed.win.cols,
            .height = if (ed.win.rows > 0) ed.win.rows - 1 else 0,
            .buf = main_buf,
        });

        try commands.registerBuiltins(&ed.cmd_map);
        try ed.scheduler.add(.Tick, 33);
        return ed;
    }
    /// Init lua VM
    pub fn startLua(self: *Editor) void {
        self.vm = api.init(self) catch null;

        self.bootstrapConfig() catch {};

        if (self.vm) |L| {
            const home = self.env.get("HOME") orelse ".";
            const init_path = std.fmt.allocPrint(self.allocator, "{s}/.config/dot/init.lua", .{home}) catch return;
            const init_path_c = self.allocator.dupeZ(u8, init_path) catch return;

            defer {
                self.allocator.free(init_path);
                self.allocator.free(init_path_c);
            }

            if (api.c.luaL_loadfilex(L, init_path_c.ptr, null) == 0) {
                if (api.c.lua_pcallk(L, 0, api.c.LUA_MULTRET, 0, 0, null) != 0) {
                    const err_msg = std.mem.span(api.c.lua_tolstring(L, -1, null));
                    self.toastNotify(err_msg, 8000, .{ .fg = ansi.White, .bg = ansi.Red, .bold = true }) catch {};
                    api.c.lua_pop(L, 1);
                } else {
                    self.toastNotify("Config loaded !", 2000, .{ .fg = ansi.Green, .bg = ansi.Black }) catch {};
                }
            } else {
                const err_msg = std.mem.span(api.c.lua_tolstring(L, -1, null));
                self.toastNotify(err_msg, 8000, .{ .fg = ansi.White, .bg = ansi.Red, .bold = true }) catch {};
                api.c.lua_pop(L, 1);
            }
        }
    }

    /// Return the `View` at index 'active_view_idx'
    pub fn getActiveView(self: *Editor) *pane.View {
        return &self.views.items[self.active_view_idx];
    }

    /// Store builtin keybind in `self.keybinds` map
    pub fn loadStandardKeyBinds(self: *Editor) !void {
        try keybinds.loadStandardKeyBinds(self);
    }

    pub fn deinit(self: *Editor) void {
        if (self.vm) |L| c.lua_close(L);
        var it_hook = self.hooks.iterator();
        while (it_hook.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.hooks.deinit();
        var it = self.pop_store.valueIterator();
        while (it.next()) |v| {
            v.deinit();
        }
        for (self.buffers.items) |b| {
            b.deinit();
            self.allocator.destroy(b);
        }

        self.renderer.deinit();
        self.buffers.deinit(self.allocator);
        self.pop_store.deinit();
        for (&self.key_binds.values) |*mm| {
            var ite = mm.keyIterator();
            while (ite.next()) |k| self.allocator.free(k.*);
            mm.deinit();
        }
        self.pending_keys.deinit(self.allocator);
        self.cmd_buf.deinit(self.allocator);
        self.views.deinit(self.allocator);
        self.cmd_map.deinit();
        self.toast_manager.deinit();
        self.ghost_manager.deinit();
        self.pum.deinit();
        self.job_manager.deinit();
        self.server_manager.deinit();
        self.ts_manager.deinit();
        if (self.clipboard) |cl| self.allocator.free(cl);
    }

    /// Push action in the `Editor.action_queue`
    pub fn pushAction(self: *Editor, action: Action) !void {
        try self.action_queue.push(action);
    }

    /// Duplicate the filename param and store it in the .filename field
    /// of the current buffer (buffers associated to the current window)
    /// NOTE: if buffer.filename is not null this function free it to avoid leaks
    pub fn loadFile(self: *Editor, filename: []const u8) !void {
        const buf_idx = self.getCurrentBufferIdx();
        const buf = self.buffers.items[buf_idx];
        const name = try buf.allocator.dupe(u8, filename);
        if (self.buffers.items[buf_idx].filename) |f| {
            self.allocator.free(f);
        }
        self.buffers.items[buf_idx].filename = name;
    }

    pub fn quit(self: *Editor) void {
        self.is_running = false;
    }

    /// Store a new keybind in `self.key_binds`
    pub fn registerKeyBind(self: *Editor, mode: Mode, key: []const u8, action: Action) !void {
        var mode_map = self.key_binds.getPtr(mode);
        const key_dupe = try self.allocator.dupe(u8, key);
        try mode_map.put(key_dupe, action);
    }

    /// Applies the logic associated with an `Action`
    pub fn execute(self: *Editor, action: Action) !void {
        const view = self.getActiveView();
        switch (action) {
            .Tick => {
                const now = std.Io.Clock.now(.real, self.io).toMilliseconds();
                var it = self.pop_store.iterator();
                var to_remove: std.ArrayList(u32) = .empty;
                defer to_remove.deinit(self.allocator);

                const need_anim_redraw = self.renderer.tickAnimations();
                if (need_anim_redraw)
                    self.is_dirty = true;

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

                if (self.toast_manager.tick()) {
                    self.needs_redraw = true;
                    self.is_dirty = true;
                }
            },
            .LuaCallback => |ref_id| {
                if (self.vm) |L| {
                    _ = api.c.lua_rawgeti(L, api.c.LUA_REGISTRYINDEX, ref_id);

                    if (api.c.lua_pcallk(L, 0, 0, 0, 0, null) != 0) {
                        const err_msg = std.mem.span(api.c.lua_tolstring(L, -1, null));
                        self.toastNotify(err_msg, 5000, .{ .fg = ansi.White, .bg = ansi.Red }) catch {};
                        api.c.lua_pop(L, 1);
                    }
                    self.needs_redraw = true;
                }
            },
            .SetMode => |m| {
                self.last_mode = self.mode;
                if (self.mode == .Command) {
                    self.cmd_buf.clearRetainingCapacity();
                }
                if (self.mode == .Insert) {
                    self.cmd_buf.clearRetainingCapacity();
                    view.buf.extmarks.clearRetainingCapacity();
                }

                if (self.mode == .Insert and m != .Insert) {
                    try view.buf.history.commit();
                }

                self.mode = m;
                _ = self.triggerHook("ModeChanged");
                self.needs_redraw = true;
            },
            .Quit => self.quit(),
            .InsertChar => |ch| {
                if (view.is_readonly) return;

                try view.buf.history.recordInsert(view.buf.gap_start, ch);

                const start_pos = view.buf.getCursorPos();
                const start_byte = @as(u32, @intCast(view.buf.gap_start));

                try view.buf.insertChar(ch);

                const end_pos = view.buf.getCursorPos();
                self.ts_manager.edit(view.buf, start_byte, start_byte, start_byte + 1, start_pos.y, start_pos.x, start_pos.y, start_pos.x, end_pos.y, end_pos.x);
                for (self.views.items) |*v| {
                    if (v.buf == view.buf) {
                        v.is_dirty = true;
                    }
                }
                self.needs_redraw = false;
            },
            .InsertNewLine => {
                if (view.is_readonly) return;
                try view.buf.history.recordInsert(view.buf.gap_start, '\n');
                const start_pos = view.buf.getCursorPos();
                const start_byte = @as(u32, @intCast(view.buf.gap_start));

                try view.buf.insertChar('\n');

                const end_pos = view.buf.getCursorPos();
                self.ts_manager.edit(view.buf, start_byte, start_byte, start_byte + 1, start_pos.y, start_pos.x, start_pos.y, start_pos.x, end_pos.y, end_pos.x);
                self.needs_redraw = true;
            },
            .DeleteChar => {
                if (view.is_readonly or view.buf.gap_start == 0) return;

                const char_to_delete = view.buf.buffer[view.buf.gap_start - 1];
                try view.buf.history.recordDelete(view.buf.gap_start - 1, char_to_delete);

                const old_pos = view.buf.getCursorPos();
                const old_end_byte = @as(u32, @intCast(view.buf.gap_start));
                const start_byte = old_end_byte - 1;

                const delete_nl = char_to_delete == '\n';
                view.buf.backspace();

                const new_pos = view.buf.getCursorPos();
                self.ts_manager.edit(view.buf, start_byte, old_end_byte, start_byte, new_pos.y, new_pos.x, old_pos.y, old_pos.x, new_pos.y, new_pos.x);

                for (self.views.items) |*v| {
                    if (v.buf == view.buf) {
                        v.is_dirty = true;
                    }
                }
                self.needs_redraw = delete_nl;
            },
            .MoveLeft => {
                try view.buf.history.commit();
                view.buf.moveCursorLeft();
                self.needs_redraw = false;
            },
            .MoveRight => {
                try view.buf.history.commit();
                view.buf.moveCursorRight();
                self.needs_redraw = false;
            },
            .MoveDown => {
                try view.buf.history.commit();
                view.buf.moveCursorDown();
                self.needs_redraw = false;
            },
            .MoveUp => {
                try view.buf.history.commit();
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
            .YankLine => {
                const bounds = view.buf.getLineBounds(view.buf.gap_start);
                if (self.clipboard) |old_clip| self.allocator.free(old_clip);
                self.clipboard = try view.buf.getLogicalRange(self.allocator, bounds.start, bounds.end);
                try self.toast_manager.push("Yanked 1 line", 2000, .{ .fg = ansi.Cyan, .bg = ansi.Black, .bold = true });
                self.needs_redraw = true;
            },
            .Paste => {
                if (view.is_readonly) return;
                if (self.clipboard) |clip| {
                    const start_pos = view.buf.getCursorPos();
                    const start_byte = @as(u32, @intCast(view.buf.gap_start));
                    for (clip) |cl| {
                        try view.buf.insertChar(cl);
                    }

                    const end_pos = view.buf.getCursorPos();
                    self.ts_manager.edit(view.buf, start_byte, start_byte, start_byte + @as(u32, @intCast(clip.len)), start_pos.y, start_pos.x, start_pos.y, start_pos.x, end_pos.y, end_pos.x);
                    try view.buf.history.recordBatchInsert(view.buf.gap_start, clip);

                    try self.toast_manager.push("Pasted", 1500, .{ .fg = ansi.Green, .bg = ansi.Black, .bold = true });
                    self.needs_redraw = true;
                } else {
                    try self.toast_manager.push("Clipboard is empty!", 2000, .{ .fg = ansi.White, .bg = ansi.Red, .bold = true });
                    self.needs_redraw = true;
                }
            },
            .CreatePop => |b| {
                const pop_id = try self.createPop(b.pos, b.size, b.duration_ms);
                if (self.pop_store.getPtr(pop_id)) |popup| {
                    try popup.write(b.text);
                }
                self.needs_redraw = true;
            },
            .CommandChar => |ch| {
                try self.cmd_buf.append(self.allocator, ch);
                if (self.mode == .Search) {
                    try view.buf.find(self.cmd_buf.items);
                }
                self.needs_redraw = true;
            },
            .CommandBackspace => {
                _ = self.cmd_buf.pop();
                if (self.mode == .Search) {
                    try view.buf.find(self.cmd_buf.items);
                }
                self.needs_redraw = true;
            },
            .ExecuteCommand => {
                if (self.mode == .Search) {
                    self.mode = self.last_mode;
                    try self.pushAction(.ClearCommandBuf);
                    self.cmd_buf.clearRetainingCapacity();
                    // view.buf.jumpToNextSearchResult();
                } else {
                    try self.executeCmd();
                }
                self.needs_redraw = true;
            },
            .NextSearchResult => {
                view.buf.jumpToNextSearchResult();
                self.needs_redraw = true;
            },
            .PrevSearchResult => {
                view.buf.jumpToPrevSearchResult();
                self.needs_redraw = true;
            },
            .ClearCommandBuf => {
                self.cmd_buf.clearRetainingCapacity();
            },
            .Undo => {
                if (view.is_readonly) return;
                try view.buf.history.undo(view.buf);
                self.needs_redraw = true;
            },
            .EOW => {
                const sep = " .(){}[];,";
                var idw = view.buf.gap_start;
                const len = view.buf.len();
                while (true) {
                    if (view.buf.charAt(idw)) |ch| {
                        if (std.mem.indexOfScalar(u8, sep, ch) == null) {
                            break;
                        }
                        idw += 1;
                    } else break;
                }

                while (idw < len) {
                    if (view.buf.charAt(idw)) |ch| {
                        if (std.mem.indexOfScalar(u8, sep, ch) != null) {
                            break;
                        }
                        idw += 1;
                    }
                }
                view.buf.jumpToLogical(idw);
            },
        }
    }

    /// Return the buffer index associated with the current view
    pub fn getCurrentBufferIdx(self: *Editor) usize {
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

    /// Create and store a new `Pop` with the param given and order to render it
    /// pos: the position of the pop on the screen (default middle)
    /// size: the size (width/height) of the pop
    /// text: the content of the pop
    /// duration_ms: the lifespan of the Pop (default: 2000)
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

    /// Parse `self.cmd_buf` call cmd_map handler if it exist
    /// clean `cmd_buf` and switch `self.mode` to `self.last_mode`
    fn executeCmd(self: *Editor) !void {
        defer {
            self.mode = self.last_mode;
            self.cmd_buf.clearRetainingCapacity();
        }

        const input = std.mem.trim(u8, self.cmd_buf.items, " \t");
        if (input.len == 0) return;

        const space_index = std.mem.indexOfScalar(u8, input, ' ');

        const cmd = if (space_index) |idx| self.cmd_buf.items[0..idx] else input;
        const args: []const u8 = if (space_index) |idx| std.mem.trim(u8, input[idx..], " \t") else "";

        const found = try self.cmd_map.execute(self, cmd, args);

        if (!found) {
            if (utils.isDigitSlice(cmd)) {
                const l = try std.fmt.parseInt(usize, cmd, 10);
                self.getActiveView().buf.jumpTo(.{ .x = 1, .y = l });
                const view = self.getActiveView();
                view.row_offset = l - (view.height / 2);
            } else {
                try self.registerPop(null, null, "Unknown command", 2000);
            }
        }
    }

    /// Create `Pop` like a .init() but assign id and store it to the pop_store
    pub fn createPop(self: *Editor, pos: utils.Pos, size: utils.Pos, duration_ms: ?i64) !u32 {
        const id = self.next_popup_id;
        const now = std.Io.Clock.now(.real, self.io).toMilliseconds();
        self.next_popup_id += 1;
        const popup = pop.Pop.init(self.allocator, id, pos, size, duration_ms, now);
        try self.pop_store.put(id, popup);

        return id;
    }

    /// Deinit all `Pop` in `self.pop_store`
    pub fn destroyPop(self: *Editor, id: u32) void {
        if (self.pop_store.fetchRemove(id)) |kv| {
            var popup = kv.value;
            popup.deinit();
        }
    }

    /// Render all `self.pop_store` popup to the screen
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

    /// Save current buffer as associated buffer filename
    /// if `buffers[current].filename` is null display an error popup
    pub fn saveFile(self: *Editor) !void {
        if (self.triggerHook("BufWritePre")) return;

        const current_buf_idx = self.getCurrentBufferIdx();
        const buf = self.buffers.items[current_buf_idx];
        const name = buf.filename orelse {
            return try self.registerPop(null, null, "No file name", 3000);
        };
        const view = self.getActiveView();

        const file = if (std.fs.path.isAbsolute(name))
            try std.Io.Dir.createFileAbsolute(self.io, name, .{})
        else
            try std.Io.Dir.cwd().createFile(self.io, name, .{});
        defer file.close(self.io);

        var writer_buf: [1024]u8 = undefined;
        var writer = file.writer(self.io, &writer_buf);

        try writer.interface.writeAll(view.buf.getFirst());
        try writer.interface.writeAll(view.buf.getSecond());
    }

    /// Split current window horizontaly in two equal parts
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

    /// Split current window verticaly in two equal parts
    pub fn splitVertical(self: *Editor, target_buf: *buffer.GapBuffer) !void {
        const active_idx = self.active_view_idx;

        const current_width = self.views.items[active_idx].width;
        if (current_width < 5) return;

        const half_width = current_width / 2;
        const remaining_width = current_width - half_width - 1;
        self.views.items[active_idx].width = half_width;

        const new_view = pane.View{
            .x = self.views.items[active_idx].x + @as(u16, @intCast(half_width)) + 1,
            .y = self.views.items[active_idx].y,
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

    /// Change `self.active_view_idx` to `idx` param
    /// if `idx` is out of bounds this function does nothing
    pub fn switchView(self: *Editor, idx: usize) void {
        if (idx < self.views.items.len) {
            self.active_view_idx = idx;
            self.needs_redraw = true;
        }
    }

    pub fn closeView(self: *Editor, idx: usize) void {
        const target = self.views.items[idx];

        for (self.views.items, 0..) |*other, i| {
            if (i == idx) continue;

            if (other.y == target.y and other.height == target.height) {
                if (other.x + other.width + 1 == target.x) {
                    other.width += target.width + 1;
                    break;
                } else if (target.x + target.width + 1 == other.x) {
                    other.x = target.x;
                    other.width += target.width + 1;
                    break;
                }
            }

            if (other.x == target.x and other.width == target.width) {
                if (other.y + other.height + 1 == target.y) {
                    other.height += target.height + 1;
                    break;
                } else if (target.y + target.height + 1 == other.y) {
                    other.y = target.y;
                    other.height += target.height + 1;
                    break;
                }
            }
        }
        _ = self.views.orderedRemove(idx);
    }

    /// Main editor loop used to:
    /// - read user input
    /// - draw screen
    /// - update scheduler
    pub fn run(self: *Editor, stdout: *std.Io.Writer) !void {
        while (self.is_running) {
            const key = try keyboard.readKey();
            try self.scheduler.update(&self.action_queue);
            while (self.job_manager.popResult()) |result| {
                if (self.vm) |L| {
                    _ = api.c.lua_rawgeti(L, api.c.LUA_REGISTRYINDEX, result.ref_id);

                    api.c.lua_pushboolean(L, if (result.success) 1 else 0);
                    if (result.output) |out| {
                        _ = api.c.lua_pushlstring(L, out.ptr, out.len);
                    } else {
                        api.c.lua_pushnil(L);
                    }

                    if (api.c.lua_pcallk(L, 2, 0, 0, 0, null) != 0) {
                        const err_msg = std.mem.span(api.c.lua_tolstring(L, -1, null));
                        self.toast_manager.push(err_msg, 5000, .{ .fg = ansi.White, .bg = ansi.Red }) catch {};
                        api.c.lua_pop(L, 1);
                    }

                    if (!result.is_server_msg) {
                        api.c.luaL_unref(L, api.c.LUA_REGISTRYINDEX, result.ref_id);
                    }
                }
                if (result.output) |out| self.allocator.free(out);
                self.needs_redraw = true;
                self.is_dirty = true;
            }

            if (key != .none) {
                self.is_dirty = true;
                switch (self.mode) {
                    .Normal => {
                        switch (key) {
                            .ascii => |ch| {
                                try self.handleKeyPress(ch);
                            },
                            .left => try self.pushAction(.MoveLeft),
                            .right => try self.pushAction(.MoveRight),
                            .down => try self.pushAction(.MoveDown),
                            .up => try self.pushAction(.MoveUp),
                            else => {
                                self.pending_keys.clearRetainingCapacity();
                            },
                        }
                    },
                    .Insert => {
                        switch (key) {
                            .escape => {
                                try self.pushAction(.{ .SetMode = .Normal });
                                self.pending_keys.clearRetainingCapacity();
                            },
                            .ascii => |ch| {
                                try self.handleKeyPress(ch);
                            },
                            .enter => try self.pushAction(.InsertNewLine),
                            .backspace => {
                                if (!self.triggerHook("BackSpace"))
                                    try self.pushAction(.DeleteChar);
                            },
                            .left => try self.pushAction(.MoveLeft),
                            .right => try self.pushAction(.MoveRight),
                            .up => try self.pushAction(.MoveUp),
                            .down => try self.pushAction(.MoveDown),
                            else => {},
                        }
                    },
                    .Command, .Search => {
                        switch (key) {
                            .escape => {
                                if (!self.triggerHook("CmdEsc")) {
                                    try self.pushAction(.{ .SetMode = .Normal });
                                }
                                self.pending_keys.clearRetainingCapacity();
                            },
                            .ascii => |ch| {
                                if (ch == '\t') {
                                    _ = self.triggerHook("CmdTab");
                                } else try self.handleKeyPress(ch);
                            },
                            .backspace => {
                                _ = self.triggerHook("CmdBackSpace");
                                try self.pushAction(.CommandBackspace);
                            },
                            .enter => {
                                if (!self.triggerHook("CmdEnter"))
                                    try self.pushAction(.ExecuteCommand);
                            },
                            .up => {
                                _ = self.triggerHook("Up");
                            },
                            .down => {
                                _ = self.triggerHook("Down");
                            },
                            .left => {
                                _ = self.triggerHook("Left");
                            },
                            .right => {
                                _ = self.triggerHook("Right");
                            },
                            else => {
                                self.pending_keys.clearRetainingCapacity();
                            },
                        }
                    },
                }
            }

            while (self.action_queue.pop()) |act| {
                try self.execute(act);
            }
            if (self.is_dirty) {
                var active = self.getActiveView();

                if (active.scroll()) {
                    self.needs_redraw = true;
                }
                var has_dirty_views = false;
                for (self.views.items, 0..) |v, i| {
                    if (v.is_dirty) has_dirty_views = true;
                    var buffer_already_processed = false;
                    for (self.views.items[0..i]) |prev| {
                        if (prev.buf == v.buf) {
                            buffer_already_processed = true;
                            break;
                        }
                    }
                    if (buffer_already_processed) continue;
                    if (v.buf.is_dirty or self.needs_redraw) {
                        var start_row = v.row_offset + 1;
                        var end_row = v.row_offset + v.height + 2;
                        for (self.views.items[i + 1 ..]) |other| {
                            if (other.buf == v.buf) {
                                start_row = @min(start_row, other.row_offset + 1);
                                end_row = @max(end_row, other.row_offset + other.height + 2);
                            }
                        }
                        self.ts_manager.parse(v.buf);
                        const start_byte = @as(u32, @intCast(v.buf.getLogicalFromRowCol(start_row, 1)));
                        const end_byte = @as(u32, @intCast(v.buf.getLogicalFromRowCol(end_row, 1)));
                        self.ts_manager.highlight(v.buf, start_byte, end_byte);
                        v.buf.is_dirty = false;
                    }
                }

                // self.ts_manager.parse(active.buf);
                // const start_byte = @as(u32, @intCast(active.buf.getLogicalFromRowCol(active.row_offset + 1, 1)));
                // const end_byte = @as(u32, @intCast(active.buf.getLogicalFromRowCol(active.row_offset + active.height + 2, 1)));
                // self.ts_manager.highlight(active.buf, start_byte, end_byte);
                // active.buf.is_dirty = false;

                if (self.needs_redraw) {
                    // try ui.refreshScreen(stdout, self);
                    try self.renderer.refreshScreen(self, stdout);
                    self.needs_redraw = false;
                } else {
                    if (has_dirty_views) {
                        try self.renderer.refreshDirtyViews(self, stdout);
                    } else {
                        try self.renderer.updateCurrentLine(self, stdout);
                    }
                }
                self.is_dirty = false;
            }

            if (self.renderer.active_animations.items.len > 0)
                try self.renderer.refreshAnimationsOnly(stdout, self);

            try stdout.flush();
            self.frame_rendered += 1;
            const now_fps = std.Io.Clock.now(.real, self.io).toMilliseconds();
            if (now_fps - self.last_fps_time >= 1000) {
                self.last_fps = self.frame_rendered;
                self.frame_rendered = 0;
                self.last_fps_time = now_fps;
            }
            try self.win.updateSize();
            if (key == .none and self.action_queue.count() == 0)
                try std.Io.sleep(self.io, std.Io.Duration{ .nanoseconds = 16_000_000 }, .real);
        }
    }

    pub fn handleKeyPress(self: *Editor, ch: u8) !void {
        try self.pending_keys.append(self.allocator, ch);

        const mode_map = self.key_binds.get(self.mode);
        const current_seq = self.pending_keys.items;

        if (mode_map.get(current_seq)) |action| {
            try self.pushAction(action);
            self.pending_keys.clearRetainingCapacity();
            return;
        }

        var is_prefix = false;
        var it = mode_map.keyIterator();
        while (it.next()) |k| {
            if (std.mem.startsWith(u8, k.*, current_seq)) {
                is_prefix = true;
                break;
            }
        }

        if (!is_prefix) {
            if (self.pending_keys.items.len == 1) {
                switch (self.mode) {
                    .Insert => {
                        if (ch == ' ') {
                            _ = self.triggerHook("SpaceInsert");
                        }
                        try self.pushAction(.{ .InsertChar = ch });
                    },
                    .Command, .Search => try self.pushAction(.{ .CommandChar = ch }),
                    .Normal => {},
                }
            }

            self.pending_keys.clearRetainingCapacity();
        }
    }

    pub fn triggerHook(self: *Editor, hook_name: []const u8) bool {
        const L = self.vm orelse return false;
        var prevent_default = false;

        if (self.hooks.get(hook_name)) |callback| {
            for (callback.items) |ref_id| {
                _ = api.c.lua_rawgeti(L, api.c.LUA_REGISTRYINDEX, ref_id);
                if (api.c.lua_pcallk(L, 0, 1, 0, 0, null) != 0) {
                    const err_msg = std.mem.span(api.c.lua_tolstring(L, -1, null));
                    self.toast_manager.push(err_msg, 5000, .{ .fg = ansi.White, .bg = ansi.Red }) catch {};
                    api.c.lua_pop(L, 1);
                } else {
                    if (api.c.lua_isboolean(L, -1) != false) {
                        if (api.c.lua_toboolean(L, -1) != 0) {
                            prevent_default = true;
                        }
                    }
                    api.c.lua_pop(L, 1);
                }
            }
        }
        return prevent_default;
    }

    fn bootstrapConfig(self: *Editor) !void {
        const home = self.env.get("HOME") orelse return;
        const config_path = try std.fmt.allocPrint(self.allocator, "{s}/.config/dot", .{home});
        defer self.allocator.free(config_path);

        std.Io.Dir.cwd().access(self.io, config_path, .{}) catch |err| {
            if (err != error.FileNotFound) return;

            var arena = std.heap.ArenaAllocator.init(self.allocator);
            defer arena.deinit();
            const aa = arena.allocator();

            const core_dir = try std.fmt.allocPrint(aa, "{s}/lua/core", .{config_path});

            try std.Io.Dir.cwd().createDirPath(self.io, core_dir);
            try std.Io.Dir.cwd().createDirPath(self.io, try std.fmt.allocPrint(aa, "{s}/lua/plugins", .{config_path}));
            try std.Io.Dir.cwd().createDirPath(self.io, try std.fmt.allocPrint(aa, "{s}/.meta", .{config_path}));

            const dot_lua_content = @embedFile("../api/dot.lua");
            const meta_file_path = try std.fmt.allocPrint(aa, "{s}/.meta/dot.lua", .{config_path});
            const meta_file = try std.Io.Dir.createFileAbsolute(self.io, meta_file_path, .{});
            try utils.dumpToFile(self.io, meta_file_path, dot_lua_content);
            meta_file.close(self.io);

            const pwd = self.env.get("PWD") orelse ".";
            const luarc_content = try std.fmt.allocPrint(aa,
                \\{{
                \\    "workspace": {{
                \\        "library": [".meta", "{s}/runtime/lua"],
                \\        "checkThirdParty": false
                \\    }},
                \\    "diagnostics": {{ "globals": ["dot"] }}
                \\}}
            , .{pwd});

            const luarc_file_path = try std.fmt.allocPrint(aa, "{s}/.luarc.json", .{config_path});
            const luarc_file = try std.Io.Dir.createFileAbsolute(self.io, luarc_file_path, .{});
            try utils.dumpToFile(self.io, luarc_file_path, luarc_content);
            luarc_file.close(self.io);

            const keymaps_content =
                \\-- Core Config File
                \\dot.print("Core loaded !")
                \\local keymaps = require("dot.keymaps")
                \\keymaps.set("n", "<C-s>", function()
                \\        dot.save_current_file()
                \\        dot.print("File saved !")
                \\end)
                \\keymaps.set("n", "dd", function()
                \\        local cursor = dot.get_cursor()
                \\        local row = cursor[1]
                \\        dot.set_lines(row, row, {})
                \\        dot.print("line " .. row .. "deleted")
                \\end)
                \\keymaps.set("n", "gg", function()
                \\        dot.jump_to(0)
                \\end)
                \\keymaps.set("n", "G", function()
                \\        dot.jump_to(9999999)
                \\end)
            ;
            const keymaps_path = try std.fmt.allocPrint(aa, "{s}/keymaps.lua", .{core_dir});
            const keymaps_file = try std.Io.Dir.createFileAbsolute(self.io, keymaps_path, .{});
            defer keymaps_file.close(self.io);
            try utils.dumpToFile(self.io, keymaps_path, keymaps_content);

            const cmd_content =
                \\local cmd = require("dot.commands")
                \\function oui()
                \\        dot.print("oui")
                \\end
                \\cmd.create("oui", oui)
            ;

            const cmd_path = try std.fmt.allocPrint(aa, "{s}/cmd.lua", .{core_dir});
            const cmd_file = try std.Io.Dir.createFileAbsolute(self.io, cmd_path, .{});
            defer cmd_file.close(self.io);
            try utils.dumpToFile(self.io, cmd_path, cmd_content);

            const init_content =
                \\-- Welcome to Dot !
                \\require("core.keymaps")
                \\require("core.cmd")
                \\local plugins = require("dot.plugin_manager")
                \\plugins.setup({
                \\        cmd_completion = true,
                \\        cmd_history = true,
                \\        dashboard = true,
                \\        lang = true,
                \\        messages = true,
                \\        treesitter = true,
                \\})
            ;
            const init_file_path = try std.fmt.allocPrint(aa, "{s}/init.lua", .{config_path});
            const init_file = try std.Io.Dir.createFileAbsolute(self.io, init_file_path, .{});
            try utils.dumpToFile(self.io, init_file_path, init_content);
            init_file.close(self.io);

            try self.toast_manager.push("Install done !", 3000, .{ .fg = ansi.White, .bg = ansi.Green, .bold = true });
        };
    }

    pub fn toastNotify(self: *Editor, msg: []const u8, duration: u32, style: Style) !void {
        try self.toast_manager.push(msg, duration, style);
        self.logMessage(msg);
    }

    pub fn logMessage(self: *Editor, msg: []const u8) void {
        var target_buf: ?*buffer.GapBuffer = null;

        for (self.buffers.items) |buf| {
            if (buf.filename) |name| {
                if (std.mem.eql(u8, name, "*Messages*")) {
                    target_buf = buf;
                    break;
                }
            }
        }

        if (target_buf == null) {
            const new_buf = self.allocator.create(buffer.GapBuffer) catch return;
            new_buf.* = buffer.GapBuffer.init(self.allocator, self.io) catch return;
            new_buf.filename = self.allocator.dupe(u8, "*Messages*") catch return;
            self.buffers.append(self.allocator, new_buf) catch return;
            target_buf = new_buf;
        }

        const msg_buf = target_buf.?;

        msg_buf.jumpToLogical(msg_buf.len());

        for (msg) |ch| {
            msg_buf.insertChar(ch) catch {};
        }
        msg_buf.insertChar('\n') catch {};

        msg_buf.is_dirty = true;
    }
};
