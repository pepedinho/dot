const std = @import("std");
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
};
