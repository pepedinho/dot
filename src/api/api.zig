const std = @import("std");
const core = @import("../core/core.zig");
const style = @import("../view/style.zig");

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

    c.lua_pushcfunction(L, api_move_right);
    c.lua_setfield(L, -2, "move_right");

    c.lua_pushcfunction(L, api_get_cursor);
    c.lua_setfield(L, -2, "get_cursor");

    c.lua_pushcfunction(L, api_get_lines);
    c.lua_setfield(L, -2, "get_lines");

    c.lua_pushcfunction(L, api_set_lines);
    c.lua_setfield(L, -2, "set_lines");

    c.lua_pushcfunction(L, api_hook_on);
    c.lua_setfield(L, -2, "hook_on");

    c.lua_pushcfunction(L, api_show_pum);
    c.lua_setfield(L, -2, "show_pum");

    c.lua_pushcfunction(L, api_hide_pum);
    c.lua_setfield(L, -2, "hide_pum");

    c.lua_pushcfunction(L, api_read_dir);
    c.lua_setfield(L, -2, "read_dir");

    c.lua_pushcfunction(L, api_get_cmdline);
    c.lua_setfield(L, -2, "get_cmdline");

    c.lua_pushcfunction(L, api_set_cmdline);
    c.lua_setfield(L, -2, "set_cmdline");

    c.lua_pushcfunction(L, api_get_win_size);
    c.lua_setfield(L, -2, "get_win_size");

    c.lua_pushcfunction(L, api_add_style);
    c.lua_setfield(L, -2, "add_style");

    c.lua_pushcfunction(L, api_clear_style);
    c.lua_setfield(L, -2, "clear_style");

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

export fn api_move_right(L: ?*c.lua_State) c_int {
    _ = L;
    const editor = global_editor orelse return 0;

    const view = editor.getActiveView();
    view.buf.moveCursorRight();
    return 0;
}

export fn api_get_cursor(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;
    const view = editor.getActiveView();
    const pos = view.buf.getCursorPos();

    c.lua_newtable(L);

    c.lua_pushinteger(L, @intCast(pos.y));
    c.lua_rawseti(L, -2, 1);

    c.lua_pushinteger(L, @intCast(pos.x));
    c.lua_rawseti(L, -2, 2);

    return 1;
}

export fn api_get_lines(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;
    const view = editor.getActiveView();

    const start_row = @as(usize, @intCast(@max(1, c.luaL_checkinteger(L, 1))));
    const end_row = @as(usize, @intCast(@max(start_row, c.luaL_checkinteger(L, 2))));

    c.lua_newtable(L);

    var current_row: usize = 1;
    var i: usize = 0;
    var line_start: usize = 0;
    var table_idx: c_int = 1;
    const buf = view.buf;
    const len = buf.len();

    while (i <= len) : (i += 1) {
        const is_eof = (i == len);
        const char = if (!is_eof) buf.charAt(i).? else '\n';

        if (char == '\n' or is_eof) {
            if (current_row >= start_row and current_row <= end_row) {
                const line_text = buf.getLogicalRange(editor.allocator, line_start, i) catch "";
                defer if (line_text.len > 0) editor.allocator.free(line_text);

                _ = c.lua_pushlstring(L, line_text.ptr, line_text.len);
                c.lua_rawseti(L, -2, table_idx);
                table_idx += 1;
            }
            current_row += 1;
            line_start = i + 1;

            if (current_row > end_row) break;
        }
    }

    return 1;
}

export fn api_set_lines(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;
    const view = editor.getActiveView();
    if (view.is_readonly) return 0;

    const start_row = @as(usize, @intCast(@max(1, c.luaL_checkinteger(L, 1))));
    const end_row = @as(usize, @intCast(@max(start_row, c.luaL_checkinteger(L, 2))));

    c.luaL_checktype(L, 3, c.LUA_TTABLE);

    const buf = view.buf;
    const len = buf.len();

    var current_row: usize = 1;
    var i: usize = 0;
    var start_idx: ?usize = null;
    var end_idx: ?usize = null;

    var deleted_newline = false;

    while (i <= len) : (i += 1) {
        if (current_row == start_row and start_idx == null) start_idx = i;

        const is_eof = (i == len);
        const char = if (!is_eof) buf.charAt(i).? else '\n';

        if (char == '\n' or is_eof) {
            if (current_row == end_row) {
                if (!is_eof) {
                    end_idx = i + 1;
                    deleted_newline = true;
                } else {
                    end_idx = i;
                    deleted_newline = false;
                }
                break;
            }
            current_row += 1;
        }
    }

    const s_idx = start_idx orelse len;
    const e_idx = end_idx orelse len;

    buf.history.commit() catch {};

    buf.jumpToLogical(e_idx);
    var del_count = e_idx - s_idx;
    while (del_count > 0) : (del_count -= 1) {
        const char_to_del = buf.charAt(buf.gap_start - 1).?;
        buf.history.recordDelete(buf.gap_start - 1, char_to_del) catch {};
        buf.backspace();
    }

    const table_len = c.luaL_len(L, 3);
    var table_idx: c_int = 1;

    while (table_idx <= table_len) : (table_idx += 1) {
        _ = c.lua_rawgeti(L, 3, table_idx);

        if (c.lua_isstring(L, -1) != 0) {
            var str_len: usize = 0;
            const str_ptr = c.lua_tolstring(L, -1, &str_len);
            const line_str = str_ptr[0..str_len];

            for (line_str) |char| {
                buf.history.recordInsert(buf.gap_start, char) catch {};
                buf.insertChar(char) catch {};
            }

            const is_last = (table_idx == table_len);
            if (!is_last or deleted_newline) {
                buf.history.recordInsert(buf.gap_start, '\n') catch {};
                buf.insertChar('\n') catch {};
            }
        }
        c.lua_pop(L, 1);
    }

    buf.history.commit() catch {};
    editor.needs_redraw = true;
    editor.is_dirty = true;

    return 0;
}

export fn api_hook_on(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;

    const hook_ptr = c.luaL_checklstring(L, 1, null);
    c.luaL_checktype(L, 2, c.LUA_TFUNCTION);

    const hook_name = std.mem.span(hook_ptr);

    const ref_id = c.luaL_ref(L, c.LUA_REGISTRYINDEX);

    var list_ptr = editor.hooks.getPtr(hook_name);

    if (list_ptr == null) {
        const key = editor.allocator.dupe(u8, hook_name) catch return 0;
        const new_list: std.ArrayList(c_int) = .empty;

        editor.hooks.put(key, new_list) catch return 0;
        list_ptr = editor.hooks.getPtr(key);
    }

    list_ptr.?.append(editor.allocator, ref_id) catch {};
    return 0;
}

export fn api_show_pum(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;

    const x = @as(u16, @intCast(c.luaL_checkinteger(L, 1)));
    const y = @as(u16, @intCast(c.luaL_checkinteger(L, 2)));
    const selected_idx = @as(usize, @intCast(c.luaL_checkinteger(L, 4)));

    c.luaL_checktype(L, 3, c.LUA_TTABLE);

    editor.pum.clear();

    const table_len = c.luaL_len(L, 3);
    var i: c_int = 1;

    while (i <= table_len) : (i += 1) {
        _ = c.lua_rawgeti(L, 3, i);
        if (c.lua_isstring(L, -1) != 0) {
            var str_len: usize = 0;
            const item_str = c.lua_tolstring(L, -1, &str_len);

            const copy = editor.allocator.dupe(u8, item_str[0..str_len]) catch continue;
            editor.pum.items.append(editor.allocator, copy) catch {};
        }
        c.lua_pop(L, 1);
    }

    editor.pum.x = x;
    editor.pum.y = y;
    editor.pum.selected_idx = selected_idx;
    editor.pum.active = true;

    editor.needs_redraw = true;
    editor.is_dirty = true;
    return 0;
}

export fn api_hide_pum(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;
    _ = L;
    editor.pum.clear();
    editor.needs_redraw = true;
    editor.is_dirty = true;
    return 0;
}

export fn api_get_cmdline(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;
    _ = c.lua_pushlstring(L, editor.cmd_buf.items.ptr, editor.cmd_buf.items.len);
    return 1;
}

export fn api_set_cmdline(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;
    const str_ptr = c.luaL_checklstring(L, 1, null);
    const text = std.mem.span(str_ptr);

    editor.cmd_buf.clearRetainingCapacity();
    editor.cmd_buf.appendSlice(editor.allocator, text) catch {};

    editor.needs_redraw = true;
    editor.is_dirty = true;
    return 0;
}

export fn api_read_dir(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;

    const path_ptr = c.luaL_checklstring(L, 1, null);
    const path = std.mem.span(path_ptr);
    const target = if (path.len == 0) "." else path;

    c.lua_newtable(L);

    var dir = std.fs.cwd().openDir(target, .{ .iterate = true }) catch {
        return 1;
    };
    defer dir.close();

    var it = dir.iterate();
    var index: c_int = 1;

    while (it.next() catch null) |entry| {
        if (entry.kind == .directory) {
            const dir_name = std.fmt.allocPrint(editor.allocator, "{s}/", .{entry.name}) catch continue;
            defer editor.allocator.free(dir_name);
            _ = c.lua_pushlstring(L, dir_name.ptr, dir_name.len);
        } else {
            _ = c.lua_pushlstring(L, entry.name.ptr, entry.name.len);
        }
        c.lua_rawseti(L, -2, index);
        index += 1;
    }
    return 1;
}

export fn api_get_win_size(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;
    const win_cols = editor.win.cols;
    const win_rows = editor.win.rows;

    c.lua_newtable(L);

    c.lua_pushinteger(L, @intCast(win_rows));
    c.lua_rawseti(L, -2, 1);

    c.lua_pushinteger(L, @intCast(win_cols));
    c.lua_rawseti(L, -2, 2);

    return 1;
}

export fn api_add_style(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;
    const view = editor.getActiveView();

    const row = @as(usize, @intCast(c.luaL_checkinteger(L, 1)));
    const col = @as(usize, @intCast(c.luaL_checkinteger(L, 2)));
    const length = @as(usize, @intCast(c.luaL_checkinteger(L, 3)));

    c.luaL_checktype(L, 4, c.LUA_TTABLE);

    var hl_style = style.Style{};

    _ = c.lua_getfield(L, 4, "fg");
    if (c.lua_isinteger(L, -1) != 0) hl_style.fg = @enumFromInt(c.lua_tointegerx(L, -1, null));
    c.lua_pop(L, 1);

    _ = c.lua_getfield(L, 4, "bg");
    if (c.lua_isinteger(L, -1) != 0) hl_style.bg = @enumFromInt(c.lua_tointegerx(L, -1, null));
    c.lua_pop(L, 1);

    _ = c.lua_getfield(L, 4, "bold");
    if (c.lua_isboolean(L, -1) != false) hl_style.bold = (c.lua_toboolean(L, -1) != 0);
    c.lua_pop(L, 1);

    _ = c.lua_getfield(L, 4, "italic");
    if (c.lua_isboolean(L, -1) != false) hl_style.italic = (c.lua_toboolean(L, -1) != 0);
    c.lua_pop(L, 1);

    const start_idx = view.buf.getLogicalFromRowCol(row, col);
    const end_idx = start_idx + length;

    view.buf.extmarks.append(editor.allocator, .{
        .logical_start = start_idx,
        .logical_end = end_idx,
        .style = hl_style,
    }) catch {};

    editor.needs_redraw = true;
    editor.is_dirty = true;
    return 0;
}

export fn api_clear_style(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;
    _ = L;
    editor.getActiveView().buf.extmarks.clearRetainingCapacity();
    editor.needs_redraw = true;
    editor.is_dirty = true;
    return 0;
}
