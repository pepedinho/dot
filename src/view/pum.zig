const std = @import("std");

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
};
