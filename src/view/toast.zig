const std = @import("std");
const ansi = @import("ansi.zig");

const Toast = struct {
    text: []const u8,
    expire_at: i64,
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

    pub fn push(self: *ToastManager, text: []const u8, duration_ms: i64) !void {
        const text_copy = try self.allocator.dupe(u8, text);

        try self.toasts.append(self.allocator, .{
            .text = text_copy,
            .expire_at = std.time.milliTimestamp() + duration_ms,
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
        var offset_y: u16 = 2;

        var i: usize = self.toasts.items.len;
        while (i > 0) {
            i -= 1;
            const toast = self.toasts.items[i];

            const display_len = toast.text.len + 4;
            const x = if (cols > display_len) cols - @as(u16, @intCast(display_len)) else 1;
            const y = if (rows > offset_y) rows - offset_y else 1;

            try ansi.goto(stdout, y, x);
            try stdout.print("\x1b[48;5;236m\x1b[38;5;159m  {s}  \x1b[0m", .{toast.text});
            offset_y += 1;
        }
    }
};
