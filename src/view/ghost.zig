const std = @import("std");
const ansi = @import("ansi.zig");
const style = @import("style.zig");

pub const GhostLine = struct {
    /// The line under wich is displayed
    buffer_row: usize,
    /// Indentation
    col_offset: usize,
    text: []const u8,
    /// before the line for e.g. "└── "
    prefix: ?[]const u8,
    theme: style.Style,
};

pub const GhostManager = struct {
    allocator: std.mem.Allocator,
    ghosts: std.ArrayList(GhostLine),

    pub fn init(allocator: std.mem.Allocator) GhostManager {
        return .{ .allocator = allocator, .ghosts = .empty };
    }

    pub fn deinit(self: *GhostManager) void {
        for (self.ghosts.items) |g| {
            self.allocator.free(g.text);
            if (g.prefix) |p| self.allocator.free(p);
        }
        self.ghosts.deinit(self.allocator);
    }

    pub fn clear(self: *GhostManager) void {
        for (self.ghosts.items) |g| {
            self.allocator.free(g.text);
            if (g.prefix) |p| self.allocator.free(p);
        }
        self.ghosts.clearRetainingCapacity();
    }

    pub fn push(self: *GhostManager, row: usize, col: usize, text: []const u8, prefix: ?[]const u8, theme: style.Style) !void {
        try self.ghosts.append(self.allocator, .{
            .buffer_row = row,
            .col_offset = col,
            .prefix = prefix,
            .text = text,
            .theme = theme,
        });
    }

    pub fn renderAtRow(self: *const GhostManager, stdout: anytype, buffer_row: usize, screen_x: u16, screen_y: u16, max_rows: u16) !u16 {
        var lines_drawn: u16 = 0;
        if (self.ghosts.items.len == 0) return lines_drawn;

        for (self.ghosts.items) |ghost| {
            if (ghost.buffer_row == buffer_row) {
                const target_y = screen_y + lines_drawn;
                if (target_y > max_rows) break;

                try ansi.goto(stdout, target_y, screen_x + @as(u16, @intCast(ghost.col_offset)));

                try ghost.theme.toAnsi(stdout);

                if (ghost.prefix) |p| try stdout.writeAll(p);
                try stdout.writeAll(ghost.text);

                try stdout.writeAll("\x1b[0m\x1b[K");

                lines_drawn += 1;
            }
        }
        return lines_drawn;
    }
};
