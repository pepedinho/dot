const std = @import("std");
const Style = @import("../style.zig").Style;
const Block = @import("block.zig").Block;
const Rect = @import("../layout.zig").Rect;
const Buffer = @import("../buffer.zig").Buffer;

pub const List = struct {
    items: []const []const u8,
    style: Style = .{},
    highlight_style: Style = .{},
    selected_index: ?usize = null,
    block: ?Block = null,

    pub fn render(self: List, area: Rect, buf: *Buffer) void {
        var current_area = area;

        if (self.block) |block| {
            const inner = block.inner(current_area);
            block.render(current_area, buf);
            current_area = inner;
        }

        if (current_area.width == 0 or current_area.height == 0) return;

        for (self.items, 0..) |item, i| {
            if (i >= current_area.height) break;

            const is_selected = if (self.selected_index) |idx| idx == i else false;
            const item_style = if (is_selected) self.highlight_style else self.style;

            const end = @min(item.len, current_area.width);

            buf.setString(
                current_area.x,
                current_area.y + @as(u16, @intCast(i)),
                item[0..end],
                item_style,
            );
        }
    }
};
