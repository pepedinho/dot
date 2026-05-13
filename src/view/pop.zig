const std = @import("std");
const utils = @import("../utils.zig");
const Editor = @import("../core/core.zig").Editor;

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
    border_color: []const u8 = "\x1b[37m",
    expire_at: ?i64,

    pub fn init(allocator: std.mem.Allocator, id: u32, pos: utils.Pos, size: utils.Pos, duration_ms: ?i64, now: i64) Pop {
        const buffer: std.ArrayList(u8) = .empty;
        const expires = if (duration_ms) |ms| now + ms else null;

        return .{
            .allocator = allocator,
            .id = id,
            .pos = pos,
            .size = size,
            .buffer = buffer,
            .expire_at = expires,
        };
    }

    pub fn deinit(self: *Pop) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn write(self: *Pop, content: []const u8) !void {
        try self.buffer.appendSlice(self.allocator, content);
    }

    pub fn clear(self: *Pop) void {
        self.buffer.clearRetainingCapacity();
    }
};

pub fn render(stdout: *std.Io.Writer, pop: *const Pop) !void {
    const x = pop.pos.x;
    const y = pop.pos.y;
    const w = pop.size.x;
    const h = pop.size.y;

    try stdout.writeAll("\x1b[?25l");
    try stdout.print("\x1b[{d};{d}H┌", .{ y, x });
    for (0..w - 2) |_| try stdout.writeAll("─");
    try stdout.writeAll("┐");

    for (1..h - 1) |i| {
        try stdout.print("\x1b[{d};{d}H│", .{ y + i, x });
        for (0..w - 2) |_| try stdout.writeAll(" ");
        try stdout.writeAll("│");
    }

    try stdout.print("\x1b[{d};{d}H└", .{ y + h - 1, x });
    for (0..w - 2) |_| try stdout.writeAll("─");
    try stdout.writeAll("┘");

    var lines = std.mem.splitScalar(u8, pop.buffer.items, '\n');
    var row_offset: usize = 1;

    const inner_w = w - 2;
    while (lines.next()) |line| {
        if (row_offset >= h - 1) break;

        const display_len = @min(line.len, w - 2);
        const left_padding = (inner_w - display_len) / 2;
        const start_x = x + 1 + left_padding;

        try stdout.print("\x1b[{d};{d}H{s}", .{ y + row_offset, start_x, line[0..display_len] });
        row_offset += 1;
    }
    try stdout.writeAll("\x1b[?25h"); // display cursor
}

//This function display a pop window of size `size` at pos `pos`
// pub fn pop(stdout: *std.Io.Writer, editor: *Editor, size: utils.Pos, pos: utils.Pos) !void {

// }
