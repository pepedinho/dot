const std = @import("std");
const gap = @import("gap.zig");
const api = @import("../api/api.zig");
const ansi = @import("../view/ansi.zig");
const c = api.c;

extern fn tree_sitter_zig() callconv(.c) *c.TSLanguage;

export fn ts_reader(payload: ?*anyopaque, byte_index: u32, position: c.TSPoint, bytes_read: ?*u32) callconv(.c) [*c]const u8 {
    _ = position;
    const buf: *gap.GapBuffer = @ptrCast(@alignCast(payload));

    const total_len = buf.len();

    if (byte_index >= total_len) {
        bytes_read.?.* = 0;
        return "";
    }

    if (byte_index < buf.gap_start) {
        bytes_read.?.* = @as(u32, @intCast(buf.gap_start - byte_index));
        return buf.buffer.ptr + byte_index;
    } else {
        const logical_offset = byte_index - buf.gap_start;
        const physical_index = buf.gap_end + logical_offset;
        bytes_read.?.* = @as(u32, @intCast(buf.buffer.len - physical_index));
        return buf.buffer.ptr + physical_index;
    }
}

pub const TSManager = struct {
    allocator: std.mem.Allocator,
    parser: *c.TSParser,
    query: ?*c.TSQuery = null,
    cursor: *c.TSQueryCursor,

    dyn_lib: ?std.DynLib = null,

    pub fn init(allocator: std.mem.Allocator) !TSManager {
        const parser = c.ts_parser_new() orelse return error.TSInitFailed;
        errdefer c.ts_parser_delete(parser);
        const cursor = c.ts_query_cursor_new() orelse return error.TSCursorFailed;

        return .{
            .allocator = allocator,
            .parser = parser,
            .cursor = cursor,
        };
    }

    pub fn deinit(self: *TSManager) void {
        c.ts_query_cursor_delete(self.cursor);
        if (self.query) |q| c.ts_query_delete(q);
        c.ts_parser_delete(self.parser);
        if (self.dyn_lib) |*lib| lib.close();
    }

    pub fn loadLanguage(self: *TSManager, buf: *gap.GapBuffer, lang_name: []const u8, lib_path: []const u8, query_path: []const u8) !void {
        if (self.dyn_lib) |*lib| lib.close();
        if (self.query) |q| c.ts_query_delete(q);
        errdefer {
            self.dyn_lib = null;
            self.query = null;
        }
        if (buf.ts_tree) |t| c.ts_tree_delete(@as(?*c.TSTree, @ptrCast(@alignCast(t))));
        buf.ts_tree = null;

        self.dyn_lib = try std.DynLib.open(lib_path);

        const symbol_name = try std.fmt.allocPrintSentinel(self.allocator, "tree_sitter_{s}", .{lang_name}, 0);
        defer self.allocator.free(symbol_name);

        const ts_lang_fn = self.dyn_lib.?.lookup(*const fn () callconv(.c) *c.TSLanguage, symbol_name) orelse return error.SymbolNotFound;
        const lang = ts_lang_fn();

        _ = c.ts_parser_set_language(self.parser, lang);

        const query_source = try std.fs.cwd().readFileAlloc(self.allocator, query_path, 1024 * 1024);
        defer self.allocator.free(query_source);

        var error_offset: u32 = 0;
        var error_type: c.TSQueryError = undefined;
        self.query = c.ts_query_new(lang, query_source.ptr, @intCast(query_source.len), &error_offset, &error_type) orelse {
            const file = std.fs.cwd().createFile("ts_error.log", .{}) catch return error.TSQueryFailed;
            defer file.close();
            file.deprecatedWriter().print("ERREUR TREE-SITTER SCM\nOffset : {d}\nType : {d}\n(1=Syntaxe, 2=Noeud Invalide, 3=Champ, 4=Capture)\n", .{ error_offset, error_type }) catch {};
            return error.TSQueryFailed;
        };
    }

    pub fn edit(
        self: *TSManager,
        buf: *gap.GapBuffer,
        start_byte: u32,
        old_end_byte: u32,
        new_end_byte: u32,
        start_y: usize,
        start_x: usize,
        old_y: usize,
        old_x: usize,
        new_y: usize,
        new_x: usize,
    ) void {
        _ = self;
        if (buf.ts_tree) |tree| {
            const ts_edit = c.TSInputEdit{
                .start_byte = start_byte,
                .old_end_byte = old_end_byte,
                .new_end_byte = new_end_byte,
                .start_point = .{ .row = @intCast(start_y - 1), .column = @intCast(start_x - 1) },
                .old_end_point = .{ .row = @intCast(old_y - 1), .column = @intCast(old_x - 1) },
                .new_end_point = .{ .row = @intCast(new_y - 1), .column = @intCast(new_x - 1) },
            };
            c.ts_tree_edit(@as(?*c.TSTree, @ptrCast(@alignCast(tree))), &ts_edit);
        }
    }

    pub fn parse(self: *TSManager, buf: *gap.GapBuffer) void {
        const input = c.TSInput{
            .payload = buf,
            .read = ts_reader,
            .encoding = c.TSInputEncodingUTF8,
        };
        const old_tree = @as(?*c.TSTree, @ptrCast(@alignCast(buf.ts_tree)));
        const new_tree = c.ts_parser_parse(self.parser, old_tree, input);

        buf.ts_tree = new_tree;

        if (old_tree) |t| c.ts_tree_delete(t);
    }

    pub fn highlight(self: *TSManager, buf: *gap.GapBuffer, start_byte: u32, end_byte: u32) void {
        const tree = @as(?*c.TSTree, @ptrCast(@alignCast(buf.ts_tree))) orelse return;
        const query = self.query orelse return;

        const root_node = c.ts_tree_root_node(tree);
        _ = c.ts_query_cursor_set_byte_range(self.cursor, start_byte, end_byte);
        c.ts_query_cursor_exec(self.cursor, query, root_node);

        var match: c.TSQueryMatch = undefined;
        var capture_index: u32 = 0;

        buf.clearMarksByNamespace(gap.NS_TREESITTER);

        while (c.ts_query_cursor_next_capture(self.cursor, &match, &capture_index)) {
            const capture = match.captures[capture_index];
            const node = capture.node;

            const s_byte = c.ts_node_start_byte(node);
            const e_byte = c.ts_node_end_byte(node);

            var length: u32 = 0;
            const name_ptr = c.ts_query_capture_name_for_id(query, capture.index, &length);
            const name = name_ptr[0..length];

            // TODO :  make this color mapping scriptable by Lua
            var color = ansi.Default;
            var italic = false;
            var bold = false;

            if (std.mem.eql(u8, name, "keyword")) {
                color = ansi.Magenta;
                bold = true;
            } else if (std.mem.eql(u8, name, "function")) {
                color = ansi.Blue;
            } else if (std.mem.eql(u8, name, "type.qualifier")) {
                color = ansi.Magenta;
                color = .{ .Rgb = .{ .r = 153, .g = 153, .b = 255 } };
            } else if (std.mem.eql(u8, name, "builtin")) {
                color = ansi.Cyan;
            } else if (std.mem.eql(u8, name, "string")) {
                color = ansi.Green;
            } else if (std.mem.eql(u8, name, "number")) {
                color = ansi.Yellow;
            } else if (std.mem.eql(u8, name, "type")) {
                color = ansi.Yellow;
                italic = true;
                bold = true;
            } else if (std.mem.eql(u8, name, "constant")) {
                color = ansi.Yellow;
                bold = true;
            } else if (std.mem.eql(u8, name, "property")) {
                color = .{ .Index = 117 };
            } else if (std.mem.eql(u8, name, "operator")) {
                color = ansi.Red;
            } else if (std.mem.eql(u8, name, "variable")) {
                color = ansi.Default;
            } else if (std.mem.eql(u8, name, "variable.parameter")) {
                color = ansi.Red;
                italic = true;
            } else if (std.mem.eql(u8, name, "comment")) {
                color = .{ .Index = 242 };
                italic = true;
            }

            buf.extmarks.append(buf.allocator, .{
                .logical_start = s_byte,
                .logical_end = e_byte,
                .style = .{ .fg = color, .italic = italic, .bold = bold },
                .ns_id = gap.NS_TREESITTER,
                .priority = 0,
            }) catch {};
        }
    }
};
