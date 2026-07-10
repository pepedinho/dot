//! A generic widget used to draw borders around a specific area.

const std = @import("std");
const Rect = @import("../layout.zig").Rect;
const Buffer = @import("../buffer.zig").Buffer;
const Style = @import("../style.zig").Style;

pub const Borders = packed struct(u8) {
    top: bool = false,
    bottom: bool = false,
    left: bool = false,
    right: bool = false,
    _pad: u4 = 0,

    pub const NONE = Borders{};
    pub const ALL = Borders{ .top = true, .bottom = true, .left = true, .right = true };
};

const BOX_TL = "┌";
const BOX_TR = "┐";
const BOX_BL = "└";
const BOX_BR = "┘";
const BOX_H = "─";
const BOX_V = "│";

pub const Block = struct {
    const Self = @This();

    borders: Borders = .NONE,
    title: ?[]const u8 = null,
    title_style: ?Style = null,
    style: Style = .{},

    pub fn init() Self {
        return .{};
    }

    pub fn inner(self: Self, area: Rect) Rect {
        var inner_area = area;

        if (self.borders.left) {
            inner_area.x += 1;
            inner_area.width -|= 1;
        }
        if (self.borders.top) {
            inner_area.y += 1;
            inner_area.height -|= 1;
        }
        if (self.borders.right) {
            inner_area.width -|= 1;
        }
        if (self.borders.bottom) {
            inner_area.height -|= 1;
        }

        return inner_area;
    }

    pub fn render(self: Self, area: Rect, buf: *Buffer) void {
        if (area.width == 0 or area.height == 0) return;

        buf.setStyleArea(area, self.style);

        const right_x = area.x + area.width - 1;
        const bottom_y = area.y + area.height - 1;

        if (self.borders.top) {
            var x: u16 = area.x;
            while (x <= right_x) : (x += 1) {
                if (buf.get(x, area.y)) |c| {
                    c.setSymbol(BOX_H);
                    c.setStyle(self.style);
                }
            }
        }
        if (self.borders.bottom) {
            var x: u16 = area.x;
            while (x <= right_x) : (x += 1) {
                if (buf.get(x, bottom_y)) |c| {
                    c.setSymbol(BOX_H);
                    c.setStyle(self.style);
                }
            }
        }

        if (self.borders.left) {
            var y: u16 = area.y;
            while (y <= bottom_y) : (y += 1) {
                if (buf.get(area.x, y)) |c| {
                    c.setSymbol(BOX_V);
                    c.setStyle(self.style);
                }
            }
        }
        if (self.borders.right) {
            var y: u16 = area.y;
            while (y <= bottom_y) : (y += 1) {
                if (buf.get(right_x, y)) |c| {
                    c.setSymbol(BOX_V);
                    c.setStyle(self.style);
                }
            }
        }

        if (self.borders.top and self.borders.left) {
            if (buf.get(area.x, area.y)) |c| {
                c.setSymbol(BOX_TL);
                c.setStyle(self.style);
            }
        }
        if (self.borders.top and self.borders.right) {
            if (buf.get(right_x, area.y)) |c| {
                c.setSymbol(BOX_TR);
                c.setStyle(self.style);
            }
        }
        if (self.borders.bottom and self.borders.left) {
            if (buf.get(area.x, bottom_y)) |c| {
                c.setSymbol(BOX_BL);
                c.setStyle(self.style);
            }
        }
        if (self.borders.bottom and self.borders.right) {
            if (buf.get(right_x, bottom_y)) |c| {
                c.setSymbol(BOX_BR);
                c.setStyle(self.style);
            }
        }

        if (self.title) |title| {
            if (self.borders.top and area.width > 4) {
                const max_x = right_x - 2;
                var current_x = area.x + 2;
                const title_style = self.title_style orelse self.style;

                var view = std.unicode.Utf8View.init(title) catch return;
                var iter = view.iterator();

                while (iter.nextCodepointSlice()) |codepoint_slice| {
                    if (current_x >= max_x) break;

                    if (buf.get(current_x, area.y)) |c| {
                        c.setSymbol(codepoint_slice);
                        c.setStyle(title_style);
                    }
                    current_x += 1;
                }
            }
        }
    }
};
