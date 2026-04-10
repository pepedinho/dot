const std = @import("std");
const ansi = @import("ansi.zig");
const style = @import("style.zig");

pub const PumSpan = struct {
    text: []const u8,
    icon: ?[]const u8 = null,
    icon_color: ?[]const u8 = null,
};

pub const PumManager = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(PumSpan),
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
        for (self.items.items) |item| {
            self.allocator.free(item.text);
            if (item.icon) |icon| {
                self.allocator.free(icon);
            }
            if (item.icon_color) |color| {
                self.allocator.free(color);
            }
        }
        self.items.clearRetainingCapacity();
        self.active = false;
    }

    pub fn render(self: *const PumManager, stdout: *std.Io.Writer) !void {
        if (!self.active or self.items.items.len == 0) return;

        var max_bytes: usize = 0;
        for (self.items.items) |item| {
            var current_bytes: usize = item.text.len;
            if (item.icon) |icon| {
                current_bytes += icon.len + 1;
            }
            if (current_bytes > max_bytes) max_bytes = current_bytes;
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

            const use_color = item.icon_color != null and !is_selected;

            var ansi_len: usize = 0;
            const reset_fg = "\x1b[39m";

            if (use_color) {
                ansi_len = item.icon_color.?.len + reset_fg.len;
            }

            const alloc_len = max_bytes + 2 + ansi_len;
            var padded_buf = try self.allocator.alloc(u8, alloc_len);
            defer self.allocator.free(padded_buf);

            var offset: usize = 0;

            padded_buf[offset] = ' ';
            offset += 1;

            if (item.icon) |icon| {
                if (use_color) {
                    const color = item.icon_color.?;
                    @memcpy(padded_buf[offset .. offset + color.len], color);
                    offset += color.len;
                }

                @memcpy(padded_buf[offset .. offset + icon.len], icon);
                offset += icon.len;

                if (use_color) {
                    @memcpy(padded_buf[offset .. offset + reset_fg.len], reset_fg);
                    offset += reset_fg.len;
                }

                padded_buf[offset] = ' ';
                offset += 1;
            }

            @memcpy(padded_buf[offset .. offset + item.text.len], item.text);
            offset += item.text.len;

            @memset(padded_buf[offset..alloc_len], ' ');

            const span = style.Span.init(padded_buf, theme);
            try span.render(stdout, 0.0);

            try stdout.writeAll("\x1b[0m");
            current_y -= 1;
        }
    }
};
