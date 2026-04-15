const std = @import("std");
const gap = @import("gap.zig");
const api = @import("../api/api.zig");
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

pub const TsManager = struct {
    parser: *c.TSParser,
    tree: ?*c.TSTree = null,

    pub fn init() !TsManager {
        const parser = c.ts_parser_new() orelse return error.TSInitFailed;
        _ = c.ts_parser_set_language(parser, tree_sitter_zig());

        return .{ .parser = parser };
    }

    pub fn deinit(self: *TsManager) void {
        if (self.tree) |tree| c.ts_tree_delete(tree);
        c.ts_parser_delete(self.parser);
    }

    pub fn parse(self: *TsManager, buf: *gap.GapBuffer) void {
        const input = c.TSInput{
            .payload = buf,
            .read = ts_reader,
            .encoding = c.TSInputEncodingUTF8,
        };

        const old_tree = self.tree;

        self.tree = c.ts_parser_parse(self.parser, old_tree, input);
        if (old_tree) |t| c.ts_tree_delete(t);
    }
};
