const std = @import("std");
const style = @import("style.zig");

const Toast = struct {
    text: []const u8,
    expire_at: i64,
    theme: style.Style,
};

pub const ToastManager = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    toasts: std.ArrayList(Toast),

    pub fn init(allocator: std.mem.Allocator, io: std.Io) ToastManager {
        return .{ .allocator = allocator, .io = io, .toasts = .empty };
    }

    pub fn deinit(self: *ToastManager) void {
        for (self.toasts.items) |t| self.allocator.free(t.text);
        self.toasts.deinit(self.allocator);
    }

    pub fn push(self: *ToastManager, text: []const u8, duration_ms: i64, theme: style.Style) !void {
        const padded_text = try std.fmt.allocPrint(self.allocator, " {s} ", .{text});
        errdefer self.allocator.free(padded_text);
        const now = std.Io.Clock.now(.real, self.io).toMilliseconds();

        try self.toasts.append(self.allocator, .{
            .text = padded_text,
            .expire_at = now + duration_ms,
            .theme = theme,
        });
    }

    pub fn tick(self: *ToastManager) bool {
        const now = std.Io.Clock.now(.real, self.io).toMilliseconds();
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
};
