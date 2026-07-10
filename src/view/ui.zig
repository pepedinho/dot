const std = @import("std");
const zui = @import("zui");
const Editor = @import("../core/core.zig").Editor;

pub fn renderSimple(editor: *Editor, frame: *zui.terminal.Frame) void {
    const view = editor.getActiveView();
    const allocator = frame.allocator;

    const gutter_area = view.getGutterArea();
    const text_area = view.getTextArea();

    var gutter_lines = allocator.alloc(zui.widgets.Line, view.height) catch return;
    var text_lines = allocator.alloc(zui.widgets.Line, view.height) catch return;

    var i: u16 = 0;
    while (i < view.height) : (i += 1) {
        const row_idx = i + view.row_offset;

        const line_num_str = std.fmt.allocPrint(allocator, "{d}", .{row_idx + 1}) catch "??";
        var gutter_spans = allocator.alloc(zui.widgets.Span, 1) catch continue;
        gutter_spans[0] = .{ .text = line_num_str, .style = .{
            .fg = .Black,
        } };
        gutter_lines[i] = .{ .spans = gutter_spans };

        const raw_line = view.buf.getLine(allocator, row_idx) catch "";
        const display_text = processTextLine(allocator, raw_line, view.col_offset, text_area.width);

        var text_spans = allocator.alloc(zui.widgets.Span, 1) catch continue;
        text_spans[0] = .{ .text = display_text };
        text_lines[i] = .{ .spans = text_spans };
    }

    var gutter_para = zui.widgets.Paragraph{ .lines = gutter_lines, .block = .{ .borders = .{ .right = true } } };
    gutter_para.render(gutter_area, frame.buffer);

    var text_para = zui.widgets.Paragraph{ .lines = text_lines };
    text_para.render(text_area, frame.buffer);

    // CURSOR

    const pos = view.buf.getCursorPos();

    if (pos.y > view.row_offset and pos.y <= view.row_offset + view.height) {
        if (pos.x > view.col_offset and pos.x <= view.col_offset + text_area.width) {
            const screen_y = text_area.y + (pos.y - 1 - view.row_offset);
            const screen_x = text_area.x + (pos.x - 1 - view.col_offset);

            frame.setCursor(@intCast(screen_x), @intCast(screen_y));
        }
    }
}

fn processTextLine(allocator: std.mem.Allocator, text: []const u8, col_offset: usize, width: u16) []const u8 {
    const start = @min(col_offset, text.len);
    const sliced = text[start..];

    if (sliced.len >= width) return sliced[0..width];

    var padded = allocator.alloc(u8, width) catch return sliced;
    @memcpy(padded[0..sliced.len], sliced);
    @memset(padded[sliced.len..], ' ');
    return padded;
}
