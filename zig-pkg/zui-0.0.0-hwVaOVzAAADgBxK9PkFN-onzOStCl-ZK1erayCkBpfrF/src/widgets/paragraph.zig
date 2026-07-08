const std = @import("std");
const Style = @import("../style.zig").Style;
const Block = @import("block.zig").Block;
const Rect = @import("../layout.zig").Rect;
const Buffer = @import("../buffer.zig").Buffer;
const Line = @import("line.zig").Line;

pub const Alignement = enum {
    Left,
    Center,
    Right,
};

pub const Paragraph = struct {
    const Self = @This();

    alignement: Alignement = .Left,
    text: ?[]const u8 = null,
    lines: ?[]const Line = null,
    block: ?Block = null,
    style: Style = .{},
    /// If this option is on `true` text inside `Paragraph` will be
    /// automaticly wrapped.
    wraping: bool = false,
    scroll_offset: usize = 0,

    pub fn init(text: []const u8) Self {
        return .{
            .text = text,
        };
    }

    pub fn render(self: Self, area: Rect, buf: *Buffer) void {
        var current_area = area;
        if (self.block) |block| {
            const inner = block.inner(current_area);
            block.render(current_area, buf);
            current_area = inner;
        }

        if (area.width == 0 or area.height == 0) {
            return;
        }

        if (self.text) |t| {
            if (self.wraping) {
                var start: usize = 0;
                var virtual_line_idx: usize = 0;
                var rendered_lines: u16 = 0;

                while (start < t.len and rendered_lines < current_area.height) {
                    const end = @min(start + current_area.width, t.len);
                    const line_text = t[start..end];

                    if (virtual_line_idx >= self.scroll_offset) {
                        const x_offset: u16 = switch (self.alignement) {
                            .Left => 0,
                            .Center => @intCast((current_area.width - line_text.len) / 2),
                            .Right => @intCast(current_area.width - line_text.len),
                        };

                        buf.setString(
                            current_area.x + x_offset,
                            current_area.y + rendered_lines,
                            line_text,
                            self.style,
                        );
                        rendered_lines += 1;
                    }

                    virtual_line_idx += 1;
                    start = end;
                }
            } else {
                if (self.scroll_offset == 0) {
                    const end = @min(t.len, current_area.width);
                    const visible_text = t[0..end];
                    const x_offset: u16 = switch (self.alignement) {
                        .Left => 0,
                        .Center => @intCast((current_area.width - visible_text.len) / 2),
                        .Right => @intCast(current_area.width - visible_text.len),
                    };

                    buf.setString(current_area.x + x_offset, current_area.y, visible_text, self.style);
                }
            }
        } else if (self.lines) |lines| {
            if (self.scroll_offset >= lines.len) return;

            const visible_lines = lines[self.scroll_offset..];

            for (visible_lines, 0..) |line, y_offset| {
                if (y_offset >= current_area.height) break;

                var x_offset: u16 = 0;
                const y = current_area.y + @as(u16, @intCast(y_offset));

                for (line.spans) |span| {
                    if (x_offset >= current_area.width) break;

                    const available_width = current_area.width - x_offset;
                    const end = @min(span.text.len, available_width);
                    const visible_text = span.text[0..end];

                    buf.setString(current_area.x + x_offset, y, visible_text, span.style);
                    x_offset += @as(u16, @intCast(visible_text.len));
                }
            }
        }
    }
};
