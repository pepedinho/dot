const Rect = @import("../layout.zig").Rect;
const Buffer = @import("../buffer.zig").Buffer;

pub const Clear = struct {
    pub fn render(self: Clear, area: Rect, buf: *Buffer) void {
        _ = self;

        for (0..area.height) |y_offset| {
            for (0..area.width) |x_offset| {
                const x = area.x + @as(u16, @intCast(x_offset));
                const y = area.y + @as(u16, @intCast(y_offset));

                buf.setCell(x, y, " ", .{});
            }
        }
    }
};
