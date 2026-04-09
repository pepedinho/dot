const std = @import("std");
const core = @import("../core/core.zig");

pub const c = @cImport({
    @cInclude("lua.h");
    @cInclude("lualib.h");
    @cInclude("lauxlib.h");
});

var global_editor: ?*core.Editor = null;

pub fn init(editor: *core.Editor) !*c.lua_State {
    global_editor = editor;

    const L = c.luaL_newstate() orelse return error.LuaInitFailed;

    c.luaL_openlibs(L);
    c.lua_newtable(L);

    c.lua_pushcfunction(L, api_print);
    c.lua_setfield(L, -2, "print");

    c.lua_pushcfunction(L, api_insert);
    c.lua_setfield(L, -2, "insert");

    c.lua_setglobal(L, "dot");
    return L;
}

export fn api_print(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;

    const str_ptr = c.luaL_checklstring(L, 1, null);
    const message = std.mem.span(str_ptr);

    editor.toast_manager.push(message, 3000, .{ .fg = .Yellow, .bg = .Black, .bold = true }) catch {};
    editor.needs_redraw = true;
    return 0;
}

export fn api_insert(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;

    const str_ptr = c.luaL_checklstring(L, 1, null);
    const text = std.mem.span(str_ptr);

    const view = editor.getActiveView();
    if (view.is_readonly) return 0;

    view.buf.history.recordBatchInsert(view.buf.gap_start, text) catch {};
    for (text) |ch| {
        view.buf.insertChar(ch) catch {};
    }

    editor.needs_redraw = true;
    return 0;
}
