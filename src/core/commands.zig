const std = @import("std");
const core = @import("core.zig");
const buffer = @import("gap.zig");
const utils = @import("../utils.zig");
const fs = @import("../fs/filesystem.zig");
const api = @import("../api/api.zig");

const Editor = core.Editor;

const cmdHandler = *const fn (editor: *Editor, args: []const u8) anyerror!void;

/// A easy to use api to manipul Command map and execute them
pub const CommandsMap = struct {
    map: std.StringArrayHashMap(cmdHandler),

    pub fn init(allocator: std.mem.Allocator) CommandsMap {
        return .{
            .map = std.StringArrayHashMap(cmdHandler).init(allocator),
        };
    }

    pub fn deinit(self: *CommandsMap) void {
        self.map.deinit();
    }

    pub fn register(self: *CommandsMap, name: []const u8, func: cmdHandler) !void {
        try self.map.put(name, func);
    }

    pub fn execute(self: *CommandsMap, editor: *Editor, name: []const u8, args: []const u8) !bool {
        if (self.map.get(name)) |handler| {
            try handler(editor, args);
            return true;
        }
        return false;
    }
};

// ==========================
// BUILT-INS CMD
// ==========================

fn cmdQ(ed: *Editor, args: []const u8) !void {
    _ = args;
    ed.quit();
}

fn cmdW(ed: *Editor, args: []const u8) !void {
    _ = args;
    try ed.saveFile();
    const current_buf_idx = ed.getCurrentBufferIdx();
    if (ed.buffers.items[current_buf_idx].filename) |filename|
        try ed.registerPop(null, null, filename, null);
}

fn cmdWq(ed: *Editor, args: []const u8) !void {
    _ = args;
    try ed.saveFile();
    const current_buf_idx = ed.getCurrentBufferIdx();
    if (ed.buffers.items[current_buf_idx].filename) |_| {
        ed.quit();
    }
}

fn cmdTop(ed: *Editor, args: []const u8) !void {
    _ = args;
    ed.getActiveView().buf.jumpTo(.{ .x = 1, .y = 1 });
}

fn cmdFile(ed: *Editor, args: []const u8) !void {
    try ed.loadFile(args);
}

fn cmdSplit(ed: *Editor, args: []const u8) !void {
    _ = args;
    const buf = try ed.allocator.create(buffer.GapBuffer);
    buf.* = try buffer.GapBuffer.init(ed.allocator);
    try ed.buffers.append(ed.allocator, buf);
    try ed.splitHorizontal(buf);
}

fn cmdVsplit(ed: *Editor, args: []const u8) !void {
    _ = args;
    const buf = try ed.allocator.create(buffer.GapBuffer);
    buf.* = try buffer.GapBuffer.init(ed.allocator);
    try ed.buffers.append(ed.allocator, buf);
    try ed.splitVertical(buf);
}

fn cmdGoto(ed: *Editor, args: []const u8) !void {
    if (utils.isDigitSlice(args)) {
        const idx = try std.fmt.parseInt(usize, args, 10);
        ed.switchView(idx);
    }
}

fn cmdOpen(ed: *Editor, args: []const u8) !void {
    const content = fs.Fs.loadFast(ed.allocator, args) catch |err| {
        try ed.registerPop(null, null, @errorName(err), null);
        return;
    };
    defer ed.allocator.free(content);

    const new_buf = try ed.allocator.create(buffer.GapBuffer);
    new_buf.* = try buffer.GapBuffer.initFromFile(ed.allocator, content, args);

    try ed.buffers.append(ed.allocator, new_buf);

    const view = ed.getActiveView();
    view.buf = new_buf;
    view.col_offset = 0;
    view.row_offset = 0;

    ed.needs_redraw = true;
}

fn cmdBprev(ed: *Editor, args: []const u8) !void {
    _ = args;
    if (ed.buffers.items.len <= 1) return;

    const current_buffer_idx = ed.getCurrentBufferIdx();

    const prev_idx = if (current_buffer_idx == 0)
        ed.buffers.items.len - 1
    else
        current_buffer_idx - 1;

    const view = ed.getActiveView();
    view.buf = ed.buffers.items[prev_idx];
    view.col_offset = 0;
    view.row_offset = 0;
    ed.needs_redraw = true;
}

fn cmdBnext(ed: *Editor, args: []const u8) !void {
    _ = args;
    if (ed.buffers.items.len <= 1) return;

    const current_buffer_idx = ed.getCurrentBufferIdx();
    const next_idx = (current_buffer_idx + 1) % ed.buffers.items.len;

    const view = ed.getActiveView();
    view.buf = ed.buffers.items[next_idx];
    view.col_offset = 0;
    view.row_offset = 0;
    ed.needs_redraw = true;
}

fn cmdDebug(ed: *Editor, args: []const u8) !void {
    _ = args;

    if (ed.debug_view_idx == null) {
        const buf = if (ed.debug_buf_idx) |i|
            ed.buffers.items[i]
        else blk: {
            const b = try ed.allocator.create(buffer.GapBuffer);
            b.* = try buffer.GapBuffer.init(ed.allocator);
            try ed.buffers.append(ed.allocator, b);
            ed.debug_buf_idx = ed.buffers.items.len - 1;
            break :blk b;
        };

        try ed.splitVertical(buf);

        const new_idx = ed.views.items.len - 1;
        ed.views.items[new_idx].is_readonly = true;
        ed.debug_view_idx = new_idx;
        try ed.scheduler.add(.{ .UpdateDebugBuffer = buf }, 100);
        ed.needs_redraw = true;
    }
}

fn cmdClose(ed: *Editor, args: []const u8) !void {
    _ = args;
    const view_idx = ed.active_view_idx;
    if (ed.views.items.len <= 1) return;
    if (ed.debug_view_idx) |i| {
        if (i == view_idx) {
            ed.debug_view_idx = null;
        }
    }
    if (view_idx == ed.views.items.len - 1 and ed.active_view_idx > 0)
        ed.active_view_idx -= 1;
    ed.closeView(view_idx);
    ed.needs_redraw = true;
}

fn cmdSource(ed: *Editor, args: []const u8) !void {
    if (ed.vm) |L| {
        const c_path = try std.fmt.allocPrint(ed.allocator, "{s}", .{args});
        defer ed.allocator.free(c_path);

        if (api.c.luaL_loadfilex(L, c_path.ptr, null) != 0 or api.c.lua_pcallk(L, 0, api.c.LUA_MULTRET, 0, 0, null) != 0) {
            const err_msg = std.mem.span(api.c.lua_tolstring(L, -1, null));
            try ed.toast_manager.push(err_msg, 5000, .{ .fg = .White, .bg = .Red, .bold = true });
            api.c.lua_settop(L, -2);
        } else {
            try ed.toast_manager.push("Lua script loaded!", 2000, .{ .fg = .Green, .bg = .Black });
        }
    }
}

pub fn registerBuiltins(map: *CommandsMap) !void {
    try map.register("q", cmdQ);
    try map.register("w", cmdW);
    try map.register("wq", cmdWq);
    try map.register("top", cmdTop);
    try map.register("file", cmdFile);
    try map.register("split", cmdSplit);
    try map.register("vsplit", cmdVsplit);
    try map.register("goto", cmdGoto);
    try map.register("open", cmdOpen);
    try map.register("bprev", cmdBprev);
    try map.register("bnext", cmdBnext);
    try map.register("debug", cmdDebug);
    try map.register("close", cmdClose);
    try map.register("source", cmdSource);
}
