const std = @import("std");
const utils = @import("../utils.zig");
const Editor = @import("../core/core.zig").Editor;

/// A single styled content row drawn inside a `Pop` frame.
pub const PopRow = struct {
    text: ?[]const u8 = null,
    fg: ?[]const u8 = null,
    bg: ?[]const u8 = null,
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,
    marker: ?[]const u8 = null,
    marker_fg: ?[]const u8 = null,
};

//This struct represent a `pop` windows.
//This will be used for popup notification,
//Pop can have a lifetime or can be killed mannually
//So it can be used for non ephemeral messages to
pub const Pop = struct {
    id: u32,
    allocator: std.mem.Allocator,
    pos: utils.Pos,
    size: utils.Pos,
    buffer: std.ArrayList(u8),
    rows: std.ArrayList(PopRow),
    pop_bg: ?[]const u8 = null,
    border_color: ?[]const u8 = null,
    border: bool = true,
    centered: bool = true,
    indicator: ?[]const u8 = null,
    expire_at: ?i64,

    pub fn init(allocator: std.mem.Allocator, id: u32, pos: utils.Pos, size: utils.Pos, duration_ms: ?i64, now: i64) Pop {
        const buffer: std.ArrayList(u8) = .empty;
        const rows: std.ArrayList(PopRow) = .empty;
        const expires = if (duration_ms) |ms| now + ms else null;

        return .{
            .allocator = allocator,
            .id = id,
            .pos = pos,
            .size = size,
            .buffer = buffer,
            .rows = rows,
            .expire_at = expires,
        };
    }

    pub fn deinit(self: *Pop) void {
        self.buffer.deinit(self.allocator);
        self.rows.deinit(self.allocator);
    }

    pub fn write(self: *Pop, content: []const u8) !void {
        try self.buffer.appendSlice(self.allocator, content);
    }

    pub fn clear(self: *Pop) void {
        self.buffer.clearRetainingCapacity();
    }
};

//This function display a pop window of size `size` at pos `pos`
// pub fn pop(stdout: *std.Io.Writer, editor: *Editor, size: utils.Pos, pos: utils.Pos) !void {

// }