//! This module provides primitives for spatial arrangement and layout constraints.
//!
//! The fundamental building block is the `Rect`, representing a 2D bounding box
//! on the terminal grid.

const std = @import("std");

pub const Direction = enum {
    Horizontal,
    Vertical,
};

pub const Constraint = union(enum) {
    Length: u16,
    Percentage: u16,
    Min: u16,
    Fill: u16,
};

pub const Layout = struct {
    const Self = @This();

    direction: Direction = .Vertical,
    constraints: []const Constraint,

    pub fn init(constraints: []const Constraint) Self {
        return .{ .constraints = constraints };
    }

    pub fn dir(self: Self, d: Direction) Self {
        var copy = self;
        copy.direction = d;
        return copy;
    }

    /// Split a `Rect` into a tab of sub-`Rect` while respecting the constraints.
    /// Use the frame allocator, memory will be freed automaticly
    pub fn split(self: Self, allocator: std.mem.Allocator, area: Rect) ![]Rect {
        const results = try allocator.alloc(Rect, self.constraints.len);

        const available_space = if (self.direction == .Horizontal) area.width else area.height;
        var fill_total: u16 = 0;
        var fixed_space: u16 = 0;

        const sizes = try allocator.alloc(u16, self.constraints.len);
        defer allocator.free(sizes);

        for (self.constraints, 0..) |c, i| {
            switch (c) {
                .Length => |l| {
                    sizes[i] = l;
                    fixed_space += l;
                },
                .Percentage => |p| {
                    const l = @as(u16, @intCast(@as(u32, available_space) * p / 100));
                    sizes[i] = l;
                    fixed_space += l;
                },
                .Min => |m| {
                    sizes[i] = m;
                    fixed_space += m;
                    fill_total += 1;
                },
                .Fill => |f| {
                    sizes[i] = 0;
                    fill_total += f;
                },
            }
        }

        const remaining = if (available_space > fixed_space) available_space - fixed_space else 0;

        if (remaining > 0 and fill_total > 0) {
            var space_to_distribute = remaining;
            var fill_left = fill_total;

            for (self.constraints, 0..) |c, i| {
                const weight = switch (c) {
                    .Min => @as(u16, 1),
                    .Fill => |f| f,
                    else => @as(u16, 0),
                };

                if (weight > 0) {
                    const extra = @as(u16, @intCast(@as(u32, space_to_distribute) * weight / fill_left));
                    sizes[i] += extra;
                    space_to_distribute -= extra;
                    fill_left -= weight;
                }
            }
        }

        var current_x = area.x;
        var current_y = area.y;

        for (sizes, 0..) |s, i| {
            if (self.direction == .Horizontal) {
                results[i] = Rect.init(current_x, current_y, s, area.height);
                current_x += s;
            } else {
                results[i] = Rect.init(current_x, current_y, area.width, s);
                current_y += s;
            }
        }

        return results;
    }
};

pub const Rect = struct {
    const Self = @This();

    x: u16,
    y: u16,
    width: u16,
    height: u16,

    /// Create a new `Rect`
    pub fn init(x: u16, y: u16, width: u16, height: u16) Self {
        return .{
            .x = x,
            .y = y,
            .width = width,
            .height = height,
        };
    }

    /// Calculates the area of the rectangle.
    pub fn area(self: Self) u32 {
        return @as(u32, self.width) * @as(u32, self.height);
    }

    /// Checks if a given point (x, y) is inside the rectangle.
    pub fn contains(self: Self, target_x: u16, target_y: u16) bool {
        return target_x >= self.x and target_x < self.x + self.width and
            target_y >= self.y and target_y < self.y + self.height;
    }

    /// Computes the intersection of this rectangle with another.
    /// Return a new `Rect` that is the overlapping area.
    /// If they do not intersect, returns a `Rect` with zero width and height.
    pub fn intersection(self: Self, other: Self) Self {
        const x1 = @max(self.x, other.x);
        const y1 = @max(self.y, other.y);

        const self_x2 = self.x + self.width;
        const other_x2 = other.x + other.width;
        const x2 = @min(self_x2, other_x2);

        const self_y2 = self.y + self.height;
        const other_y2 = other.y + other.height;
        const y2 = @min(self_y2, other_y2);

        if (x1 >= x2 or y1 >= y2) {
            return Rect.init(0, 0, 0, 0); // No intersection
        }

        return Rect.init(x1, y1, x2 - x1, y2 - y1);
    }
};

test "Rect contains point" {
    const r = Rect.init(5, 5, 10, 10);

    // Inside
    try std.testing.expect(r.contains(5, 5));
    try std.testing.expect(r.contains(14, 14));

    // Outside
    try std.testing.expect(!r.contains(4, 5));
    try std.testing.expect(!r.contains(15, 15));
}

test "Rect intersection" {
    const r1 = Rect.init(0, 0, 10, 10);
    const r2 = Rect.init(5, 5, 10, 10);

    const intersect = r1.intersection(r2);

    try std.testing.expectEqual(@as(u16, 5), intersect.x);
    try std.testing.expectEqual(@as(u16, 5), intersect.y);
    try std.testing.expectEqual(@as(u16, 5), intersect.width);
    try std.testing.expectEqual(@as(u16, 5), intersect.height);

    // No intersection
    const r3 = Rect.init(20, 20, 5, 5);
    const no_intersect = r1.intersection(r3);
    try std.testing.expectEqual(@as(u16, 0), no_intersect.area());
}

test "Layout: Vertical split with Length and Percentage" {
    const allocator = std.testing.allocator;
    const area = Rect.init(0, 0, 50, 100); // Écran de 50x100

    const layout = Layout.init(&.{
        .{ .Length = 20 }, // Fixe: 20 of height
        .{ .Percentage = 50 }, // 50% de 100: 50 of height
    }).dir(.Vertical);

    const chunks = try layout.split(allocator, area);
    defer allocator.free(chunks);

    try std.testing.expectEqual(@as(usize, 2), chunks.len);

    // Le premier bloc prend les 20 premières lignes
    try std.testing.expectEqual(Rect.init(0, 0, 50, 20), chunks[0]);
    // Le deuxième prend 50 lignes, juste en dessous
    try std.testing.expectEqual(Rect.init(0, 20, 50, 50), chunks[1]);
}

test "Layout: Horizontal split with Fill and Min" {
    const allocator = std.testing.allocator;
    const area = Rect.init(0, 0, 100, 10); // Écran large de 100

    const layout = Layout.init(&.{
        .{ .Length = 10 },
        .{ .Min = 20 },
        .{ .Fill = 2 },
    }).dir(.Horizontal);

    // Expected Mathematic :
    // Fix total space = 10 + 20 = 30
    // To be distribute = 100 - 30 = 70
    // Total weight = 1 (for Min) + 2 (for Fill) = 3
    // Min bonus = 70 * 1 / 3 = 23 -> Total Min = 20 + 23 = 43
    // Fill bonus = 70 - 23 = 47 -> Total Fill = 47

    const chunks = try layout.split(allocator, area);
    defer allocator.free(chunks);

    try std.testing.expectEqual(@as(usize, 3), chunks.len);

    try std.testing.expectEqual(Rect.init(0, 0, 10, 10), chunks[0]);
    try std.testing.expectEqual(Rect.init(10, 0, 43, 10), chunks[1]);
    try std.testing.expectEqual(Rect.init(53, 0, 47, 10), chunks[2]);
}
