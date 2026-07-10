//! This module defines the memory grid used for double-buffered rendering.
//!
//! Rather than printing directly to the terminal, widgets draw themselves onto a `Buffer`.
//! The core struct is `Cell`, representing a single character cell on the screen.

const std = @import("std");
const Style = @import("style.zig").Style;

/// Represents a single character cell on the terminal screen.
pub const Cell = struct {
    const Self = @This();

    /// The string content of the cell. Usually a single character,
    /// but stored as a slice to support multi-byte UTF-8 graphemes.
    /// Default is a single space.
    symbol_buf: [15]u8 = [_]u8{' '} ++ [_]u8{0} ** 14,
    symbol_len: u8 = 1,

    /// The visual style (colors and modifiers) applied to this cell.
    style: Style = .{},

    /// Reset the call to an empty space with default styling.
    pub fn reset(self: *Self) void {
        self.symbol_buf[0] = ' ';
        self.symbol_len = 1;
        self.style = .init();
    }

    /// Sets the symbol of the cell.
    pub fn setSymbol(self: *Self, symbol: []const u8) void {
        const len = @min(symbol.len, 15);
        @memcpy(self.symbol_buf[0..len], symbol[0..len]);
        self.symbol_len = @as(u8, @intCast(len));
    }

    pub fn getSymbol(self: *const Self) []const u8 {
        return self.symbol_buf[0..self.symbol_len];
    }

    /// Sets the style of the cell.
    pub fn setStyle(self: *Self, style: Style) void {
        self.style = style;
    }
};

/// A 2D grid of `Cell`s, represented internally as a 1D array for memory efficiency.
pub const Buffer = struct {
    const Self = @This();

    width: u16,
    height: u16,
    content: []Cell,

    /// Allocates a new buffer of the given dimensions.
    pub fn init(allocator: std.mem.Allocator, width: u16, height: u16) !Self {
        const s = @as(usize, width) * @as(usize, height);
        const content = try allocator.alloc(Cell, s);

        for (content) |*cell| {
            cell.reset();
        }

        return .{
            .width = width,
            .height = height,
            .content = content,
        };
    }

    /// Frees the buffer memory.
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.content);
    }

    /// Writes a raw string to the buffer starting at (x, y).
    /// Uses a UTF-8 iterator to pplace one codepoint per cell.
    /// Stop if it reaches the end of the buffer width
    pub fn setString(self: *Self, x: u16, y: u16, string: []const u8, style: Style) void {
        var current_x = x;

        var view = std.unicode.Utf8View.init(string) catch return;
        var iter = view.iterator();

        while (iter.nextCodepointSlice()) |codepoint_slice| {
            if (current_x >= self.width) break;

            if (self.get(current_x, y)) |cell| {
                cell.setSymbol(codepoint_slice);
                cell.setStyle(style);
            }
            current_x += 1;
        }
    }

    /// Change a specific `Cell` with its coordinates.
    pub fn setCell(self: *Self, x: u16, y: u16, symbol: []const u8, style: Style) void {
        const cell = self.get(x, y);
        if (cell) |c| {
            c.setSymbol(symbol);
            c.setStyle(style);
        }
    }

    /// Writes a styled `Span` to the buffer starting at (x, y)
    pub fn setSpan(self: *Self, x: u16, y: u16, span: *const @import("text.zig").Span) void {
        self.setString(x, y, span.content, span.style);
    }

    /// Writes a `Line` (a sequence of Spans) to the buffer starting at (x, y).
    /// Returns the new X position after writing the line.
    pub fn setLine(self: *Self, x: u16, y: u16, line: *const @import("text.zig").Line, max_width: u16) usize {
        var current_x = x;
        const end_x = @min(self.width, x + max_width);

        for (line.spans) |span| {
            if (current_x >= end_x) break;

            var view = std.unicode.Utf8View.init(span.content) catch continue;
            var iter = view.iterator();

            while (iter.nextCodepointSlice()) |codepoint_slice| {
                if (current_x >= end_x) break;

                if (self.get(current_x, y)) |cell| {
                    cell.setSymbol(codepoint_slice);
                    cell.setStyle(span.style);
                }
                current_x += 1;
            }
        }

        return current_x;
    }

    /// Applies a style to a specific rectangular area in the buffer.
    /// This is useful for filling the background of a block or rendering borders.
    pub fn setStyleArea(self: *Self, area: @import("layout.zig").Rect, style: Style) void {
        const start_x = area.x;
        const end_x = @min(self.width, area.x + area.width);
        const start_y = area.y;
        const end_y = @min(self.height, area.y + area.height);

        var y: u16 = start_y;
        while (y < end_y) : (y += 1) {
            var x: u16 = start_x;
            while (x < end_x) : (x += 1) {
                if (self.get(x, y)) |cell| {
                    cell.style = cell.style.patch(style);
                }
            }
        }
    }

    /// Returns a pointer to the cell at the specified coordinates.
    /// Returns `null` if the coordinates are out of bounds.
    pub fn get(self: *Self, x: u16, y: u16) ?*Cell {
        if (x >= self.width or y >= self.height) return null;
        const index = (@as(usize, y) * @as(usize, self.width)) + @as(usize, x);

        return &self.content[index];
    }

    /// Resets all cells in the buffer to empty spaces.
    pub fn reset(self: *Self) void {
        for (self.content) |*cell| {
            cell.reset();
        }
    }
};

test "Buffer initialization and access" {
    const allocator = std.testing.allocator;

    var buf = try Buffer.init(allocator, 10, 5);
    defer buf.deinit(allocator);

    try std.testing.expectEqual(@as(u16, 10), buf.width);
    try std.testing.expectEqual(@as(usize, 50), buf.content.len);

    if (buf.get(2, 3)) |cell| {
        cell.setSymbol("X");
    } else {
        return error.ExpectedCell;
    }

    const check_cell = buf.get(2, 3).?;
    try std.testing.expectEqualStrings("X", check_cell.getSymbol());

    try std.testing.expectEqual(@as(?*Cell, null), buf.get(10, 5));
}

test "Buffer setString with UTF-8" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 10, 5);
    defer buf.deinit(allocator);

    // "Hé" is 3 bytes, but 2 codepoints.
    buf.setString(0, 0, "Hé", Style.init());

    const cell_0 = buf.get(0, 0).?;
    const cell_1 = buf.get(1, 0).?;
    const cell_2 = buf.get(2, 0).?; // Should be empty

    try std.testing.expectEqualStrings("H", cell_0.getSymbol());
    try std.testing.expectEqualStrings("é", cell_1.getSymbol());
    try std.testing.expectEqualStrings(" ", cell_2.getSymbol());
}
