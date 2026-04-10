const std = @import("std");
const ansi = @import("ansi.zig");
const style = @import("style.zig");

pub const PumManager = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList([]const u8),
    active: bool = false,
    x: u16 = 0,
    y: u16 = 0,
    selected_idx: usize = 0,

    pub fn init(allocator: std.mem.Allocator) PumManager {
        return .{
            .allocator = allocator,
            .items = .empty,
        };
    }

    pub fn deinit(self: *PumManager) void {
        self.clear();
        self.items.deinit(self.allocator);
    }

    pub fn clear(self: *PumManager) void {
        for (self.items.items) |item| self.allocator.free(item);
        self.items.clearRetainingCapacity();
        self.active = false;
    }

    pub fn render(self: *const PumManager, stdout: *std.Io.Writer) !void {
        if (!self.active or self.items.items.len == 0) return;

        var max_width: usize = 0;
        for (self.items.items) |item| {
            if (item.len > max_width) max_width = item.len;
        }

        try stdout.writeAll(ansi.hide_cursor);

        var current_y: u16 = self.y - 1;

        for (self.items.items, 0..) |item, i| {
            if (current_y == 0) break;

            try ansi.goto(stdout, current_y, self.x);

            const is_selected = (i == self.selected_idx);
            const theme = if (is_selected)
                style.Style{ .fg = .Black, .bg = .White, .bold = true }
            else
                style.Style{ .fg = .White, .bg = .Black };

            const padded_len = max_width + 2;
            var padded_buf = try self.allocator.alloc(u8, padded_len);
            defer self.allocator.free(padded_buf);

            @memset(padded_buf, ' ');
            @memcpy(padded_buf[1 .. 1 + item.len], item);

            const span = style.Span.init(padded_buf, theme);
            try span.render(stdout, 0.0);

            try stdout.writeAll("\x1b[0m");
            current_y -= 1;
        }
    }
};
