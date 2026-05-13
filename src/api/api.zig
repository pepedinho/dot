const std = @import("std");
const core = @import("../core/core.zig");
const style = @import("../view/style.zig");
const job = @import("../core/worker.zig");
const ansi = @import("../view/ansi.zig");
const utils = @import("../utils.zig");
const gap = @import("../core/gap.zig");

pub const c = @cImport({
    @cInclude("lua.h");
    @cInclude("lualib.h");
    @cInclude("lauxlib.h");
    @cInclude("tree_sitter/api.h");
});

var global_editor: ?*core.Editor = null;

fn parseLuaColor(L: ?*c.lua_State, field_name: [:0]const u8) style.Color {
    _ = c.lua_getfield(L, -1, field_name.ptr);
    defer c.lua_pop(L, 1);

    if (c.lua_type(L, -1) == c.LUA_TNUMBER) {
        return .{ .Index = @as(u8, @intCast(c.lua_tointegerx(L, -1, null))) };
    } else if (c.lua_type(L, -1) == c.LUA_TSTRING) {
        const hex_ptr = c.lua_tolstring(L, -1, null);
        const hex = std.mem.span(hex_ptr);

        if (hex.len == 7 and hex[0] == '#') {
            const r = std.fmt.parseInt(u8, hex[1..3], 16) catch return .Default;
            const g = std.fmt.parseInt(u8, hex[3..5], 16) catch return .Default;
            const b = std.fmt.parseInt(u8, hex[5..7], 16) catch return .Default;
            return .{ .Rgb = .{ .r = r, .g = g, .b = b } };
        }
    }
    return .Default;
}

fn registerFn(L: ?*c.lua_State, name: [:0]const u8, func: c.lua_CFunction) void {
    c.lua_pushcfunction(L, func);
    c.lua_setfield(L, -2, name.ptr);
}

fn getIntField(L: ?*c.lua_State, table_idx: c_int, key: [:0]const u8) ?u8 {
    _ = c.lua_getfield(L, table_idx, key.ptr);
    defer c.lua_pop(L, 1);

    if (c.lua_isinteger(L, -1) != 0) {
        return @as(u8, @intCast(c.lua_tointegerx(L, -1, null)));
    }
    return null;
}

fn getBoolField(L: ?*c.lua_State, table_idx: c_int, key: [:0]const u8) ?bool {
    _ = c.lua_getfield(L, table_idx, key.ptr); // Pousse la valeur en -1
    defer c.lua_pop(L, 1); // On nettoie

    if (c.lua_isboolean(L, -1) != false) {
        return (c.lua_toboolean(L, -1) != 0);
    }
    return null;
}

fn get_lua_string(L: ?*c.lua_State, allocator: std.mem.Allocator) ?[]const u8 {
    if (c.lua_isstring(L, -1) == 0) return null;

    var len: usize = 0;
    const ptr = c.lua_tolstring(L, -1, &len);
    return allocator.dupe(u8, ptr[0..len]) catch null;
}

fn get_table_string_field(L: ?*c.lua_State, allocator: std.mem.Allocator, field_name: [:0]const u8) ?[]const u8 {
    _ = c.lua_getfield(L, -1, field_name.ptr);

    defer c.lua_pop(L, 1);

    return get_lua_string(L, allocator);
}

pub fn init(editor: *core.Editor) !*c.lua_State {
    global_editor = editor;

    const L = c.luaL_newstate() orelse return error.LuaInitFailed;

    c.luaL_openlibs(L);
    c.lua_newtable(L);

    registerFn(L, "print", api_print);
    registerFn(L, "insert", api_insert);
    registerFn(L, "move_right", api_move_right);
    registerFn(L, "get_cursor", api_get_cursor);
    registerFn(L, "get_lines", api_get_lines);
    registerFn(L, "set_lines", api_set_lines);
    registerFn(L, "hook_on", api_hook_on);
    registerFn(L, "show_pum", api_show_pum);
    registerFn(L, "hide_pum", api_hide_pum);
    registerFn(L, "read_dir", api_read_dir);
    registerFn(L, "get_cmdline", api_get_cmdline);
    registerFn(L, "set_cmdline", api_set_cmdline);
    registerFn(L, "get_win_size", api_get_win_size);
    registerFn(L, "add_style", api_add_style);
    registerFn(L, "clear_style", api_clear_style);
    registerFn(L, "spawn", api_spawn);
    registerFn(L, "start_server", api_start_server);
    registerFn(L, "server_send", api_server_send);
    registerFn(L, "get_mode", api_get_mode);
    registerFn(L, "get_file", api_get_file);
    registerFn(L, "add_ghost", api_add_ghost);
    registerFn(L, "clear_ghosts", api_clear_ghosts);
    registerFn(L, "set_keymap", api_set_keymap);
    registerFn(L, "save_current_file", api_save_current_file);
    registerFn(L, "get_native_cmds", api_get_native_cmds);
    registerFn(L, "set_mode", api_set_mode);
    registerFn(L, "jump_to", api_jump_to);
    registerFn(L, "hsplit", api_hsplit);
    registerFn(L, "vsplit", api_vsplit);
    registerFn(L, "ts_parse", api_ts_parse);
    registerFn(L, "ts_load_language", api_ts_load_language);
    registerFn(L, "create_buffer", api_create_buffer);
    registerFn(L, "get_buffer_by_name", api_get_buffer_by_name);
    registerFn(L, "set_view_buffer", api_set_view_buffer);
    registerFn(L, "append_to_buffer", api_append_to_buffer);
    registerFn(L, "set_buffer_lines", api_set_buffer_lines);
    registerFn(L, "set_buffer_cursor", api_set_buffer_cursor);
    registerFn(L, "add_buffer_style", api_add_buffer_style);
    registerFn(L, "clear_buffer_style", api_clear_buffer_style);
    registerFn(L, "get_debug_info", api_get_debug_info);
    registerFn(L, "set_interval", api_set_interval);

    c.lua_setglobal(L, "dot");

    const home = editor.env.get("HOME") orelse ".";
    const pwd = editor.env.get("PWD") orelse ".";

    const lua_path_setup = std.fmt.allocPrint(editor.allocator,
        \\package.path = package.path .. 
        \\';{s}/.config/dot/lua/?.lua;{s}/.config/dot/lua/?/init.lua' ..
        \\';{s}/runtime/lua/?.lua;{s}/runtime/lua/?/init.lua'
    , .{ home, home, pwd, pwd }) catch return L;

    const lua_path_c = editor.allocator.dupeZ(u8, lua_path_setup) catch return L;
    defer {
        editor.allocator.free(lua_path_setup);
        editor.allocator.free(lua_path_c);
    }

    if (c.luaL_loadstring(L, lua_path_c.ptr) == 0) {
        _ = c.lua_pcallk(L, 0, c.LUA_MULTRET, 0, 0, null);
    }

    return L;
}

export fn api_print(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;

    const str_ptr = c.luaL_checklstring(L, 1, null);
    const message = std.mem.span(str_ptr);

    editor.toastNotify(message, 3000, .{ .fg = ansi.Yellow, .bg = ansi.Black, .bold = true }) catch {};
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

fn internal_set_lines(
    L: ?*c.lua_State,
    editor: *core.Editor,
    buf: *core.buffer.GapBuffer,
    start_row: usize,
    end_row: usize,
    table_stack_idx: c_int,
) void {
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

    buf.jumpToLogical(s_idx);
    const ts_start_pos = buf.getCursorPos();
    const ts_start_byte = @as(u32, @intCast(s_idx));

    buf.jumpToLogical(e_idx);
    const ts_old_end_pos = buf.getCursorPos();
    const ts_old_end_byte = @as(u32, @intCast(e_idx));

    var del_count = e_idx - s_idx;
    while (del_count > 0) : (del_count -= 1) {
        const char_to_del = buf.charAt(buf.gap_start - 1).?;
        if (!buf.disable_history) {
            buf.history.recordDelete(buf.gap_start - 1, char_to_del) catch {};
        }
        buf.backspace();
    }

    const table_len = c.luaL_len(L, table_stack_idx);
    var t_idx: c_int = 1;

    while (t_idx <= table_len) : (t_idx += 1) {
        _ = c.lua_rawgeti(L, table_stack_idx, t_idx);

        if (c.lua_isstring(L, -1) != 0) {
            var str_len: usize = 0;
            const str_ptr = c.lua_tolstring(L, -1, &str_len);
            const line_str = str_ptr[0..str_len];

            for (line_str) |char| {
                if (!buf.disable_history) {
                    buf.history.recordInsert(buf.gap_start, char) catch {};
                }
                buf.insertChar(char) catch {};
            }

            const is_last = (t_idx == table_len);
            if (!is_last or deleted_newline) {
                if (!buf.disable_history) {
                    buf.history.recordInsert(buf.gap_start, '\n') catch {};
                }
                buf.insertChar('\n') catch {};
            }
        }
        c.lua_pop(L, 1);
    }

    const ts_new_end_pos = buf.getCursorPos();
    const ts_new_end_byte = @as(u32, @intCast(buf.gap_start));

    editor.ts_manager.edit(
        buf,
        ts_start_byte,
        ts_old_end_byte,
        ts_new_end_byte,
        ts_start_pos.y,
        ts_start_pos.x,
        ts_old_end_pos.y,
        ts_old_end_pos.x,
        ts_new_end_pos.y,
        ts_new_end_pos.x,
    );

    buf.is_dirty = true;
    if (!buf.disable_history) {
        buf.history.commit() catch {};
    }
    editor.needs_redraw = true;
    editor.is_dirty = true;
}

export fn api_set_lines(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;
    const view = editor.getActiveView();
    if (view.is_readonly) return 0;

    const start_row = @as(usize, @intCast(@max(1, c.luaL_checkinteger(L, 1))));
    const end_row = @as(usize, @intCast(@max(start_row, c.luaL_checkinteger(L, 2))));

    c.luaL_checktype(L, 3, c.LUA_TTABLE);

    internal_set_lines(L, editor, view.buf, start_row, end_row, 3);

    return 0;
}

export fn api_set_buffer_lines(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;

    const buf_id = @as(usize, @intCast(c.luaL_checkinteger(L, 1)));
    const start_row = @as(usize, @intCast(@max(1, c.luaL_checkinteger(L, 2))));
    const end_row = @as(usize, @intCast(@max(start_row, c.luaL_checkinteger(L, 3))));

    c.luaL_checktype(L, 4, c.LUA_TTABLE);

    if (buf_id >= editor.buffers.items.len) return 0;
    const target_buf = editor.buffers.items[buf_id];

    internal_set_lines(L, editor, target_buf, start_row, end_row, 4);

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
        defer c.lua_pop(L, 1);

        var text_copy: ?[]const u8 = null;
        var icon_copy: ?[]const u8 = null;
        var color_copy: ?[]const u8 = null;

        if (c.lua_istable(L, -1)) {
            text_copy = get_table_string_field(L, editor.allocator, "text");
            icon_copy = get_table_string_field(L, editor.allocator, "icon");
            color_copy = get_table_string_field(L, editor.allocator, "icon_color");
        } else {
            text_copy = get_lua_string(L, editor.allocator);
        }

        if (text_copy) |txt| {
            editor.pum.items.append(editor.allocator, .{
                .text = txt,
                .icon = icon_copy,
                .icon_color = color_copy,
            }) catch {
                editor.allocator.free(txt);
                if (icon_copy) |icn| editor.allocator.free(icn);
                if (color_copy) |clr| editor.allocator.free(clr);
            };
        }
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

    var dir = if (std.fs.path.isAbsolute(target))
        std.Io.Dir.openDirAbsolute(editor.io, target, .{ .iterate = true }) catch return 1
    else
        std.Io.Dir.cwd().openDir(editor.io, target, .{ .iterate = true }) catch return 1;

    defer dir.close(editor.io);

    var it = dir.iterate();
    var index: c_int = 1;

    while (it.next(editor.io) catch null) |entry| {
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

    const ns_id = @as(u32, @intCast(c.luaL_checkinteger(L, 1)));

    const row = @as(usize, @intCast(c.luaL_checkinteger(L, 2)));
    const col = @as(usize, @intCast(c.luaL_checkinteger(L, 3)));
    const length = @as(usize, @intCast(c.luaL_checkinteger(L, 4)));

    c.luaL_checktype(L, 5, c.LUA_TTABLE);

    const priority = @as(u8, @intCast(c.luaL_optinteger(L, 6, 50)));

    var hl_style = style.Style{};

    if (c.lua_istable(L, 5)) {
        c.lua_pushvalue(L, 5);

        hl_style.fg = parseLuaColor(L, "fg");
        hl_style.bg = parseLuaColor(L, "bg");

        _ = c.lua_getfield(L, -1, "italic");
        hl_style.italic = c.lua_toboolean(L, -1) != 0;
        c.lua_pop(L, 1);

        _ = c.lua_getfield(L, -1, "bold");
        hl_style.bold = c.lua_toboolean(L, -1) != 0;
        c.lua_pop(L, 1);

        _ = c.lua_getfield(L, -1, "underline");
        hl_style.underline = c.lua_toboolean(L, -1) != 0;
        c.lua_pop(L, 1);

        c.lua_pop(L, 1);
    }

    const start_idx = view.buf.getLogicalFromRowCol(row, col);
    const end_idx = view.buf.getLogicalFromRowCol(row, col + length);

    view.buf.extmarks.append(editor.allocator, .{
        .logical_start = start_idx,
        .logical_end = end_idx,
        .style = hl_style,
        .ns_id = ns_id,
        .priority = priority,
    }) catch {};

    editor.needs_redraw = true;
    editor.is_dirty = true;
    return 0;
}

export fn api_clear_style(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;

    const ns_id = @as(u32, @intCast(c.luaL_checkinteger(L, 1)));

    editor.getActiveView().buf.clearMarksByNamespace(ns_id);

    editor.needs_redraw = true;
    editor.is_dirty = true;
    return 0;
}

export fn api_spawn(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;

    const cmd_ptr = c.luaL_checklstring(L, 1, null);
    const cmd_str = std.mem.span(cmd_ptr);

    c.luaL_checktype(L, 2, c.LUA_TFUNCTION);

    const cmd_copy = editor.allocator.dupe(u8, cmd_str) catch return 0;

    const ref_id = c.luaL_ref(L, c.LUA_REGISTRYINDEX);

    const thread = std.Thread.spawn(.{}, job.workerThread, .{ &editor.job_manager, editor.allocator, editor.io, cmd_copy, ref_id }) catch {
        editor.allocator.free(cmd_copy);
        c.luaL_unref(L, c.LUA_REGISTRYINDEX, ref_id);
        return 0;
    };

    thread.detach();

    return 0;
}

export fn api_start_server(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;

    const cmd_ptr = c.luaL_checklstring(L, 1, null);
    const cmd_str = std.mem.span(cmd_ptr);

    c.luaL_checktype(L, 2, c.LUA_TFUNCTION);

    var arena = std.heap.ArenaAllocator.init(editor.allocator);
    const arena_alloc = arena.allocator();

    var args: std.ArrayList([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, cmd_str, ' ');
    while (it.next()) |arg| {
        if (arg.len > 0) args.append(arena_alloc, arg) catch {};
    }

    if (args.items.len == 0) {
        arena.deinit();
        return 0;
    }

    const child = editor.allocator.create(std.process.Child) catch {
        arena.deinit();
        return 0;
    };

    // child.* = std.process.Child.init(args.items, editor.allocator);
    // child.* = std.process.Child{
    //     .allocator = editor.allocator,
    //     .argv = args.items,
    // };
    // child.stdin_behavior = .Pipe;
    // child.stdout_behavior = .Pipe;
    // child.stderr_behavior = .Ignore;

    const options = std.process.SpawnOptions{
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .ignore,
        .argv = args.items,
    };

    // child.spawn() catch {
    //     editor.allocator.destroy(child);
    //     arena.deinit();
    //     return 0;
    // };
    child.* = std.process.spawn(editor.io, options) catch {
        editor.allocator.destroy(child);
        arena.deinit();
        return 0;
    };

    arena.deinit();

    const server_id = editor.server_manager.next_id;
    editor.server_manager.next_id += 1;
    editor.server_manager.servers.put(server_id, child) catch {};

    const ref_id = c.luaL_ref(L, c.LUA_REGISTRYINDEX);

    editor.toastNotify("before run the thread", 3000, .{}) catch {};
    const thread = std.Thread.spawn(.{}, job.serverReaderThread, .{ &editor.job_manager, editor.allocator, editor.io, child, ref_id }) catch {
        child.kill(editor.io);
        return 0;
    };
    thread.detach();

    c.lua_pushinteger(L, @intCast(server_id));
    return 1;
}

export fn api_server_send(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;
    const server_id = @as(u32, @intCast(c.luaL_checkinteger(L, 1)));
    const msg_ptr = c.luaL_checklstring(L, 2, null);
    const msg = std.mem.span(msg_ptr);

    if (editor.server_manager.servers.get(server_id)) |child| {
        if (child.stdin) |stdin| {
            var pipe_buf: [1024]u8 = undefined;
            var pipe_writer = stdin.writer(editor.io, &pipe_buf);
            pipe_writer.interface.writeAll(msg) catch {};
            pipe_writer.flush() catch {};
        }
    }

    return 0;
}

export fn api_get_mode(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;
    const mode_name = @tagName(editor.mode);
    _ = c.lua_pushlstring(L, mode_name, mode_name.len);
    return 1;
}

export fn api_get_file(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;
    const view = editor.getActiveView();
    const filename = if (view.buf.filename) |f| f else "";

    _ = c.lua_pushlstring(L, filename.ptr, filename.len);
    return 1;
}

export fn api_add_ghost(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;

    const row = @as(usize, @intCast(c.luaL_checkinteger(L, 1))) - 1;
    var col = @as(usize, @intCast(c.luaL_checkinteger(L, 2))) - 1;

    const text_ptr = c.luaL_checklstring(L, 3, null);
    const text_str = std.mem.span(text_ptr);
    const text_copy = editor.allocator.dupe(u8, text_str) catch return 0;

    var prefix_copy: ?[]const u8 = null;

    if (c.lua_type(L, 4) == c.LUA_TSTRING) {
        const prefix_ptr = c.lua_tolstring(L, 4, null);
        prefix_copy = editor.allocator.dupe(u8, std.mem.span(prefix_ptr)) catch null;
    }

    var theme = style.Style{};
    if (c.lua_istable(L, 5)) {
        c.lua_pushvalue(L, 5);

        theme.fg = parseLuaColor(L, "fg");
        theme.bg = parseLuaColor(L, "bg");

        _ = c.lua_getfield(L, -1, "italic");
        theme.italic = c.lua_toboolean(L, -1) != 0;
        c.lua_pop(L, 1);

        _ = c.lua_getfield(L, -1, "bold");
        theme.bold = c.lua_toboolean(L, -1) != 0;
        c.lua_pop(L, 1);

        _ = c.lua_getfield(L, -1, "underline");
        theme.underline = c.lua_toboolean(L, -1) != 0;
        c.lua_pop(L, 1);

        c.lua_pop(L, 1);
    }
    if (prefix_copy) |p| {
        const visible_len = std.unicode.utf8CountCodepoints(p) catch p.len;
        col += visible_len;
    }

    editor.ghost_manager.push(row, col, text_copy, prefix_copy, theme) catch {};

    editor.needs_redraw = true;
    editor.is_dirty = true;
    return 0;
}

export fn api_clear_ghosts(L: ?*c.lua_State) c_int {
    _ = L;
    const editor = global_editor orelse return 0;
    editor.ghost_manager.clear();

    editor.needs_redraw = true;
    editor.is_dirty = true;

    return 0;
}

export fn api_set_keymap(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;

    const mode_str = std.mem.span(c.luaL_checklstring(L, 1, null));
    if (mode_str.len == 0) return 0;

    const target_mode: core.Mode = switch (mode_str[0]) {
        'n' => .Normal,
        'i' => .Insert,
        'c' => .Command,
        'v' => .Search,
        else => return 0,
    };

    const key_str = std.mem.span(c.luaL_checklstring(L, 2, null));
    const parsed_key = utils.parseKeySequence(editor.allocator, key_str) catch return 0;

    c.luaL_checktype(L, 3, c.LUA_TFUNCTION);
    const ref_id = c.luaL_ref(L, c.LUA_REGISTRYINDEX);

    var mode_map = editor.key_binds.getPtr(target_mode);
    mode_map.put(parsed_key, .{ .LuaCallback = ref_id }) catch {};
    return 0;
}

export fn api_save_current_file(L: ?*c.lua_State) c_int {
    _ = L;
    const editor = global_editor orelse return 0;
    editor.saveFile() catch {
        // TODO: return error message
    };

    return 0;
}

export fn api_get_native_cmds(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;
    c.lua_newtable(L);

    var index: c_int = 1;
    const cmds = editor.cmd_map.map.keys();

    for (cmds) |cmd| {
        c.lua_pushinteger(L, index);
        _ = c.lua_pushlstring(L, cmd.ptr, cmd.len);
        c.lua_settable(L, -3);
        index += 1;
    }

    return 1;
}

export fn api_set_mode(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;
    const mode_str = std.mem.span(c.luaL_checklstring(L, 1, null));
    if (mode_str.len == 0) return 0;
    const target_mode: core.Mode = switch (mode_str[0]) {
        'n' => .Normal,
        'i' => .Insert,
        'c' => .Command,
        'v' => .Search,
        else => return 0,
    };

    editor.last_mode = editor.mode;
    editor.mode = target_mode;
    return 0;
}

export fn api_jump_to(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;
    const row = c.luaL_checkinteger(L, 1);
    editor.getActiveView().buf.jumpTo(.{ .y = @as(usize, @intCast(row)), .x = 0 });
    return 0;
}

export fn api_hsplit(L: ?*c.lua_State) c_int {
    _ = L;
    const editor = global_editor orelse return 0;
    const buf = editor.getActiveView().buf;
    editor.splitHorizontal(buf) catch {};
    return 0;
}

export fn api_vsplit(L: ?*c.lua_State) c_int {
    _ = L;
    const editor = global_editor orelse return 0;
    const buf = editor.getActiveView().buf;
    editor.splitVertical(buf) catch {};
    return 0;
}

export fn api_ts_load_language(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;
    const view = editor.getActiveView();

    const lang_name_ptr = c.luaL_checklstring(L, 1, null);
    const lib_path_ptr = c.luaL_checklstring(L, 2, null);
    const query_path_ptr = c.luaL_checklstring(L, 3, null);

    const lang_name = std.mem.span(lang_name_ptr);
    const lib_path = std.mem.span(lib_path_ptr);
    const query_path = std.mem.span(query_path_ptr);

    editor.ts_manager.loadLanguage(editor.io, view.buf, lang_name, lib_path, query_path) catch |err| {
        const err_msg = std.fmt.allocPrint(editor.allocator, "TS Load Error: {s}", .{@errorName(err)}) catch return 0;
        defer editor.allocator.free(err_msg);
        editor.toastNotify(err_msg, 5000, .{ .fg = ansi.White, .bg = ansi.Red }) catch {};
        return 0;
    };

    editor.needs_redraw = true;
    editor.is_dirty = true;

    return 0;
}

export fn api_ts_parse(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;
    const view = editor.getActiveView();

    editor.ts_manager.parse(view.buf);

    if (view.buf.ts_tree) |tree| {
        const root_node = c.ts_tree_root_node(@as(?*c.TSTree, @ptrCast(@alignCast(tree))));

        const string_ptr = c.ts_node_string(root_node);
        defer c.free(string_ptr);
        const ast_string = std.mem.span(string_ptr);
        _ = c.lua_pushlstring(L, ast_string.ptr, ast_string.len);
        return 1;
    }
    return 0;
}

export fn api_create_buffer(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;

    const name_ptr = c.luaL_checklstring(L, 1, null);
    const filename = std.mem.span(name_ptr);

    const new_buf = editor.allocator.create(gap.GapBuffer) catch return 0;
    new_buf.* = gap.GapBuffer.init(editor.allocator, editor.io) catch return 0;

    new_buf.filename = editor.allocator.dupe(u8, filename) catch return 0;
    if (filename.len > 0 and filename[0] == '*') {
        new_buf.disable_history = true;
    }

    editor.buffers.append(editor.allocator, new_buf) catch return 0;

    const buf_id = editor.buffers.items.len - 1;
    c.lua_pushinteger(L, @intCast(buf_id));
    return 1;
}

export fn api_get_buffer_by_name(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;

    const name_ptr = c.luaL_checklstring(L, 1, null);
    const target_name = std.mem.span(name_ptr);

    for (editor.buffers.items, 0..) |b, i| {
        if (b.filename) |f| {
            if (std.mem.eql(u8, f, target_name)) {
                c.lua_pushinteger(L, @intCast(i));
                return 1;
            }
        }
    }

    c.lua_pushnil(L);
    return 1;
}

export fn api_set_view_buffer(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;

    const buf_id = @as(usize, @intCast(c.luaL_checkinteger(L, 1)));

    if (buf_id >= editor.buffers.items.len) return 0;

    const view = editor.getActiveView();
    const target_buf = editor.buffers.items[buf_id];

    view.buf = target_buf;
    view.col_offset = 0;

    const total_lines = target_buf.getCursorPos().y;
    view.row_offset = if (total_lines > view.height) total_lines - view.height else 0;

    view.is_readonly = true;

    editor.needs_redraw = true;
    editor.is_dirty = true;
    return 0;
}

export fn api_append_to_buffer(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;

    const buf_id = @as(usize, @intCast(c.luaL_checkinteger(L, 1)));
    const text_ptr = c.luaL_checklstring(L, 2, null);
    const text = std.mem.span(text_ptr);

    if (buf_id >= editor.buffers.items.len) return 0;

    const target_buf = editor.buffers.items[buf_id];

    target_buf.jumpToLogical(target_buf.len());

    for (text) |ch| {
        target_buf.insertChar(ch) catch {};
    }
    target_buf.insertChar('\n') catch {};

    target_buf.is_dirty = true;
    editor.needs_redraw = true;
    editor.is_dirty = true;

    return 0;
}

export fn api_set_buffer_cursor(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;
    const buf_id = @as(usize, @intCast(c.luaL_checkinteger(L, 1)));
    const row = @as(usize, @intCast(c.luaL_checkinteger(L, 2)));
    const col = @as(usize, @intCast(c.luaL_checkinteger(L, 3)));

    if (buf_id >= editor.buffers.items.len) return 0;
    const target_buf = editor.buffers.items[buf_id];

    target_buf.jumpTo(.{ .y = row, .x = col });
    return 0;
}

export fn api_add_buffer_style(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;

    const buf_id = @as(usize, @intCast(c.luaL_checkinteger(L, 1)));
    if (buf_id >= editor.buffers.items.len) return 0;
    const target_buf = editor.buffers.items[buf_id];

    const ns_id = @as(u32, @intCast(c.luaL_checkinteger(L, 2)));
    const row = @as(usize, @intCast(c.luaL_checkinteger(L, 3)));
    const col = @as(usize, @intCast(c.luaL_checkinteger(L, 4)));
    const length = @as(usize, @intCast(c.luaL_checkinteger(L, 5)));

    c.luaL_checktype(L, 6, c.LUA_TTABLE);
    const priority = @as(u8, @intCast(c.luaL_optinteger(L, 7, 50)));

    var hl_style = style.Style{};
    if (c.lua_istable(L, 6)) {
        c.lua_pushvalue(L, 6);
        hl_style.fg = parseLuaColor(L, "fg");
        hl_style.bg = parseLuaColor(L, "bg");
        _ = c.lua_getfield(L, -1, "italic");
        hl_style.italic = c.lua_toboolean(L, -1) != 0;
        c.lua_pop(L, 1);
        _ = c.lua_getfield(L, -1, "bold");
        hl_style.bold = c.lua_toboolean(L, -1) != 0;
        c.lua_pop(L, 1);
        _ = c.lua_getfield(L, -1, "underline");
        hl_style.underline = c.lua_toboolean(L, -1) != 0;
        c.lua_pop(L, 1);
        c.lua_pop(L, 1);
    }

    const start_idx = target_buf.getLogicalFromRowCol(row, col);
    const end_idx = target_buf.getLogicalFromRowCol(row, col + length);

    target_buf.extmarks.append(editor.allocator, .{
        .logical_start = start_idx,
        .logical_end = end_idx,
        .style = hl_style,
        .ns_id = ns_id,
        .priority = priority,
    }) catch {};

    editor.needs_redraw = true;
    editor.is_dirty = true;
    return 0;
}

export fn api_clear_buffer_style(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;

    const buf_id = @as(usize, @intCast(c.luaL_checkinteger(L, 1)));
    if (buf_id >= editor.buffers.items.len) return 0;
    const target_buf = editor.buffers.items[buf_id];

    const ns_id = @as(u32, @intCast(c.luaL_checkinteger(L, 2)));
    target_buf.clearMarksByNamespace(ns_id);

    editor.needs_redraw = true;
    editor.is_dirty = true;
    return 0;
}

export fn api_get_debug_info(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;
    c.lua_newtable(L);

    c.lua_pushinteger(L, @intCast(editor.last_fps));
    c.lua_setfield(L, -2, "fps");

    c.lua_pushinteger(L, @intCast(std.Io.Clock.now(.real, editor.io).toMilliseconds()));
    c.lua_setfield(L, -2, "timestamp");

    var total_mem: usize = 0;
    for (editor.buffers.items) |b| {
        total_mem += b.buffer.len;
    }
    c.lua_pushinteger(L, @intCast(total_mem / 1024));
    c.lua_setfield(L, -2, "mem_kb");

    c.lua_pushinteger(L, @intCast(editor.action_queue.count()));
    c.lua_setfield(L, -2, "queue_size");

    c.lua_newtable(L);
    for (editor.buffers.items, 0..) |b, i| {
        c.lua_newtable(L);
        const logical_size = b.buffer.len - (b.gap_end - b.gap_start);

        c.lua_pushinteger(L, @intCast(logical_size));
        c.lua_setfield(L, -2, "logical_size");
        c.lua_pushinteger(L, @intCast(b.gap_start));
        c.lua_setfield(L, -2, "gap_start");
        c.lua_pushinteger(L, @intCast(b.gap_end));
        c.lua_setfield(L, -2, "gap_end");
        c.lua_pushinteger(L, @intCast(b.len()));
        c.lua_setfield(L, -2, "len");

        const fname = if (b.filename) |f| f else "none";
        _ = c.lua_pushlstring(L, fname.ptr, fname.len);
        c.lua_setfield(L, -2, "filename");

        c.lua_rawseti(L, -2, @intCast(i + 1));
    }
    c.lua_setfield(L, -2, "buffers");

    c.lua_newtable(L);
    for (editor.views.items, 0..) |view_item, i| {
        c.lua_newtable(L);

        var b_idx: usize = 0;
        for (editor.buffers.items, 0..) |b, j| {
            if (b == view_item.buf) {
                b_idx = j;
                break;
            }
        }

        c.lua_pushinteger(L, @intCast(b_idx));
        c.lua_setfield(L, -2, "buf_idx");
        c.lua_pushboolean(L, if (i == editor.active_view_idx) 1 else 0);
        c.lua_setfield(L, -2, "is_active");
        c.lua_pushinteger(L, @intCast(view_item.x));
        c.lua_setfield(L, -2, "x");
        c.lua_pushinteger(L, @intCast(view_item.y));
        c.lua_setfield(L, -2, "y");
        c.lua_pushinteger(L, @intCast(view_item.width));
        c.lua_setfield(L, -2, "width");
        c.lua_pushinteger(L, @intCast(view_item.height));
        c.lua_setfield(L, -2, "height");
        c.lua_pushboolean(L, if (view_item.is_readonly) 1 else 0);
        c.lua_setfield(L, -2, "is_readonly");

        c.lua_rawseti(L, -2, @intCast(i + 1));
    }
    c.lua_setfield(L, -2, "views");

    c.lua_newtable(L);
    var curr = editor.action_queue.tail;
    var count: usize = 0;
    var lua_idx: c_int = 1;
    while (curr != editor.action_queue.head and count < 10) : (curr = (curr + 1) % editor.action_queue.buffer.len) {
        const act = editor.action_queue.buffer[curr];
        const act_name = @tagName(std.meta.activeTag(act));
        _ = c.lua_pushlstring(L, act_name.ptr, act_name.len);
        c.lua_rawseti(L, -2, lua_idx);
        lua_idx += 1;
        count += 1;
    }
    c.lua_setfield(L, -2, "actions");

    return 1;
}

export fn api_set_interval(L: ?*c.lua_State) c_int {
    const editor = global_editor orelse return 0;

    const interval_ms = @as(i64, @intCast(c.luaL_checkinteger(L, 1)));

    if (interval_ms <= 0) {
        return c.luaL_error(L, "interval_ms must be > 0");
    }

    c.luaL_checktype(L, 2, c.LUA_TFUNCTION);

    const ref_id = c.luaL_ref(L, c.LUA_REGISTRYINDEX);

    editor.scheduler.add(.{ .LuaCallback = ref_id }, interval_ms) catch {
        c.luaL_unref(L, c.LUA_REGISTRYINDEX, ref_id);
        return 0;
    };

    return 0;
}
