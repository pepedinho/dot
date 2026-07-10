const std = @import("std");
const Style = @import("../style.zig").Style;
const Block = @import("block.zig").Block;
const Rect = @import("../layout.zig").Rect;
const Buffer = @import("../buffer.zig").Buffer;

pub const Gauge = struct {
    percent: f32,
    style: Style = .{},
    filled_char: []const u8 = "█",
    empty_char: []const u8 = "░",
    block: ?Block = null,

    pub fn render(self: Gauge, area: Rect, buf: *Buffer) void {
        var current_area = area;

        if (self.block) |block| {
            const inner = block.inner(current_area);
            block.render(current_area, buf);
            current_area = inner;
        }

        if (current_area.width == 0 or current_area.height == 0) return;

        const clamped_percent = @max(0.0, @min(1.0, self.percent));

        const width_f = @as(f32, @floatFromInt(current_area.width));
        const filled_width = @as(u16, @intFromFloat(@round(width_f * clamped_percent)));

        for (0..current_area.height) |y_offset| {
            const y = current_area.y + @as(u16, @intCast(y_offset));

            for (filled_width..current_area.width) |x_offset| {
                buf.setString(current_area.x + @as(u16, @intCast(x_offset)), y, self.empty_char, self.style);
            }
        }
    }
};
