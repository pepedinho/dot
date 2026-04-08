const std = @import("std");
const ansi = @import("ansi.zig");
const style = @import("style.zig");

const Toast = struct {
    text: []const u8,
    expire_at: i64,
    theme: style.Style,
};

pub const ToastManager = struct {
    allocator: std.mem.Allocator,
    toasts: std.ArrayList(Toast),

    pub fn init(allocator: std.mem.Allocator) ToastManager {
        return .{ .allocator = allocator, .toasts = .empty };
    }

    pub fn deinit(self: *ToastManager) void {
        for (self.toasts.items) |t| self.allocator.free(t.text);
        self.toasts.deinit(self.allocator);
    }

    pub fn push(self: *ToastManager, text: []const u8, duration_ms: i64, theme: style.Style) !void {
        const padded_text = try std.fmt.allocPrint(self.allocator, " {s} ", .{text});

        try self.toasts.append(self.allocator, .{
            .text = padded_text,
            .expire_at = std.time.milliTimestamp() + duration_ms,
            .theme = theme,
        });
    }

    pub fn tick(self: *ToastManager) bool {
        const now = std.time.milliTimestamp();
        var need_redraws = false;

        var i: usize = 0;
        while (i < self.toasts.items.len) {
            if (now >= self.toasts.items[i].expire_at) {
                self.allocator.free(self.toasts.items[i].text);
                _ = self.toasts.orderedRemove(i);
                need_redraws = true;
            } else {
                i += 1;
            }
        }
        return need_redraws;
    }

    pub fn render(self: *const ToastManager, stdout: *std.Io.Writer, cols: u16, rows: u16) !void {
        if (self.toasts.items.len == 0) return;

        try stdout.writeAll(ansi.hide_cursor);
        var offset_y: u16 = 1;

        var i: usize = self.toasts.items.len;
        while (i > 0) {
            i -= 1;
            const toast = self.toasts.items[i];

            const display_len = toast.text.len + 4;
            const x = if (cols > display_len) cols - @as(u16, @intCast(display_len)) else 1;
            const y = if (rows > offset_y) rows - offset_y else 1;

            try ansi.goto(stdout, y, x);
            const span = style.Span.init(toast.text, toast.theme);
            try span.render(stdout, 0.0);
            try stdout.writeAll("\x1b[0m");
            offset_y += 1;
        }
    }
};
