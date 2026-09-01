const std = @import("std");
const zui = @import("zui");
const Editor = @import("../core/core.zig").Editor;
const View = @import("../core/pane.zig").View;
const ansi = @import("ansi.zig");

const MODE = [_][]const u8{ "NORMAL", "INSERT", "COMMAND", "SEARCH" };
const TAB_SIZE: u16 = 4;

/// Module-level animation clock shared by the whole renderer.
pub var animation_phase: f32 = 0.0;

/// A region of the screen that is animated between frames.
pub const AnimatedRegion = struct {
    x: usize,
    y: usize,
    span: zui.Span,
};

/// The standalone Rendering Engine backed by the `zui` TUI library.
///
/// All drawing happens into a `zui.terminal.Frame.buffer`. The four rendering
/// speeds all perform a full redraw: zui's double-buffer diffing handles the
/// per-cell optimization for us.
pub const Renderer = struct {
    allocator: std.mem.Allocator,
    active_animations: std.ArrayList(AnimatedRegion),

    pub fn init(allocator: std.mem.Allocator) Renderer {
        return .{
            .allocator = allocator,
            .active_animations = .empty,
        };
    }

    pub fn deinit(self: *Renderer) void {
        self.active_animations.deinit(self.allocator);
    }

    /// Advances the internal animation clock.
    /// Returns true if the screen should be redrawn to update animations.
    pub fn tickAnimations(self: *Renderer) bool {
        if (self.active_animations.items.len == 0) return false;

        animation_phase += 0.5;
        if (animation_phase > 1000.0) animation_phase = 0.0;

        return true;
    }

    // ==========================================
    // CORE RENDERING PIPELINE
    // ==========================================

    /// Speed 1: Full Screen Redraw. This is also the canonical entry point.
    pub fn renderToFrame(self: *Renderer, editor: *Editor, frame: *zui.terminal.Frame) void {
        self.active_animations.clearRetainingCapacity();

        const buf = frame.buffer;

        for (editor.views.items) |*view| {
            self.renderView(buf, editor, view);
        }

        self.traceBorder(buf, editor);
        self.drawStatusLine(buf, editor);

        if (editor.mode == .Command or editor.mode == .Search) {
            self.drawCommandPrompt(buf, editor);
        }

        self.renderPopups(buf, editor);
        self.renderToasts(buf, editor);
        self.renderPum(buf, editor);

        self.placeCursor(editor, frame);
    }

    /// Speed 2: Targeted Redraw - always a full redraw under zui.
    pub fn refreshDirtyViews(self: *Renderer, editor: *Editor, frame: *zui.terminal.Frame) void {
        self.renderToFrame(editor, frame);
    }

    /// Speed 3: Micro Redraw (Active Line Only) - always a full redraw under zui.
    pub fn updateCurrentLine(self: *Renderer, editor: *Editor, frame: *zui.terminal.Frame) void {
        self.renderToFrame(editor, frame);
    }

    /// Rendering Speed 4: Animations Only - always a full redraw under zui.
    pub fn refreshAnimationsOnly(self: *Renderer, editor: *Editor, frame: *zui.terminal.Frame) void {
        self.renderToFrame(editor, frame);
    }

    // ==========================================
    // UI COMPONENTS
    // ==========================================

    /// Renders the Status Line with the mode, filename (shimmer) and padding.
    fn drawStatusLine(self: *Renderer, buf: *zui.Buffer, editor: *Editor) void {
        const row = if (editor.win.rows > 0) editor.win.rows - 1 else 0;
        if (buf.height == 0 or row >= buf.height) return;

        const mode_idx = @intFromEnum(editor.mode);
        const mode_str = MODE[mode_idx];

        const mode_bg: zui.Color = switch (editor.mode) {
            .Normal => .Cyan,
            .Insert => .Green,
            .Command => .Red,
            .Search => .Yellow,
        };
        const mode_style = zui.Style{ .bg = mode_bg, .fg = .Black, .add_modifier = .{ .bold = true } };

        var x: u16 = 0;
        buf.setString(x, row, mode_str, mode_style);
        x +|= @intCast(mode_str.len);

        buf.setString(x, row, " | ", .{});
        x +|= 3;

        const buf_idx = editor.getCurrentBufferIdx();
        if (editor.buffers.items[buf_idx].filename) |f| {
            const shimmer_opts = ansi.ShimmerOptions{
                .base_color = .{ .r = 100, .g = 100, .b = 100 },
                .highlight_color = .{ .r = 255, .g = 215, .b = 0 },
                .wave_width = 6.0,
            };

            const filename_style = zui.Style{ .fg = .{ .RGB = .{ .r = 100, .g = 100, .b = 100 } }, .add_modifier = .{ .bold = true } };
            buf.setString(x, row, f, filename_style);

            ansi.applyShimmerToBuffer(buf, x, row, f, animation_phase, shimmer_opts);

            const span = zui.Span{ .content = f, .style = filename_style };
            self.active_animations.append(self.allocator, .{
                .x = x,
                .y = row,
                .span = span,
            }) catch {};

            x +|= @intCast(f.len);
        } else {
            buf.setString(x, row, "[No Name]", .{ .fg = .White, .add_modifier = .{ .italic = true } });
            x +|= 9;
        }

        // Pad the remainder of the status line with a subtle background.
        if (x < buf.width) {
            const header_bg = zui.Style{ .bg = .{ .ANSI = 236 } };
            const padding_len = buf.width - x;
            var pad_row: [256]u8 = undefined;
            const n = @min(padding_len, pad_row.len);
            @memset(pad_row[0..n], ' ');
            buf.setString(x, row, pad_row[0..n], header_bg);
        }
    }

    /// Draws the command/search prompt over the status line, after the mode block.
    fn drawCommandPrompt(self: *Renderer, buf: *zui.Buffer, editor: *Editor) void {
        _ = self;
        const row = if (editor.win.rows > 0) editor.win.rows - 1 else 0;
        if (buf.height == 0 or row >= buf.height) return;

        const mode_idx = @intFromEnum(editor.mode);
        const offset: u16 = @intCast(MODE[mode_idx].len + 3);

        // Clear the rest of the status line so residual text (e.g. filename)
        // doesn't bleed behind the command/search prompt.
        if (offset < buf.width) {
            const clear_len = buf.width - offset;
            var pad_row: [256]u8 = undefined;
            const n = @min(clear_len, pad_row.len);
            @memset(pad_row[0..n], ' ');
            buf.setString(offset, row, pad_row[0..n], .{ .bg = .Black });
        }

        var x = offset;
        const prompt_char: u8 = if (editor.mode == .Search) '/' else ':';
        if (x < buf.width) {
            buf.setCell(x, row, &[_]u8{prompt_char}, .{ .fg = .Yellow, .bg = .Black, .add_modifier = .{ .bold = true } });
            x += 1;
        }

        if (x < buf.width and editor.cmd_buf.items.len > 0) {
            const max = @min(editor.cmd_buf.items.len, buf.width - x);
            buf.setString(x, row, editor.cmd_buf.items[0..max], .{ .fg = .White, .bg = .Black });
        }
    }

    /// Places the cursor based on the editor mode.
    fn placeCursor(self: *Renderer, editor: *Editor, frame: *zui.terminal.Frame) void {
        _ = self;
        const buf = frame.buffer;

        if (editor.mode == .Command or editor.mode == .Search) {
            const mode_idx = @intFromEnum(editor.mode);
            const offset: u16 = @intCast(MODE[mode_idx].len + 3);
            const cmd_len: u16 = @intCast(@min(editor.cmd_buf.items.len, 1024));
            var cursor_x = offset + cmd_len + 1;
            if (cursor_x >= buf.width) cursor_x = if (buf.width > 0) buf.width - 1 else 0;
            const cursor_y = if (editor.win.rows > 0) editor.win.rows - 1 else 0;
            frame.setCursor(cursor_x, cursor_y);
            return;
        }

        const view = editor.getActiveView();
        const pos = view.buf.getCursorPos();

        var layout_shift: usize = 0;
        for (editor.ghost_manager.ghosts.items) |g| {
            if (g.buffer_row < pos.y - 1) {
                layout_shift += 1;
            }
        }

        const screen_y = view.y +% @as(u16, @intCast(pos.y)) -% view.row_offset -% 1 +% @as(u16, @intCast(layout_shift));
        const screen_x = view.x +% view.gutter_width +% @as(u16, @intCast(pos.x)) -% view.col_offset -% 1;

        const zx = if (screen_x > 0) screen_x - 1 else 0;
        const zy = if (screen_y > 0) screen_y - 1 else 0;

        if (zx < buf.width and zy < buf.height) {
            frame.setCursor(@intCast(zx), @intCast(zy));
        }
    }

    // ==========================================
    // VIEW / TEXT RENDERING
    // ==========================================

    fn renderView(self: *Renderer, buf: *zui.Buffer, editor: *Editor, view: *View) void {
        const part1 = view.buf.getFirst();
        const part2 = view.buf.getSecond();

        var current_row: usize = 1;
        var current_col: usize = 1;

        var screen_row: u16 = view.y;
        const max_rows = view.y + view.height - 1;

        const text_width = view.width - view.gutter_width;
        var need_gutter = true;
        var current_style: zui.Style = .{};

        const parts = [_][]const u8{ part1, part2 };
        for (parts, 0..) |part, p_idx| {
            for (part, 0..) |c, c_idx| {
                if (screen_row > max_rows) break;

                if (need_gutter and current_row > view.row_offset) {
                    self.drawGutter(buf, view, current_row, screen_row);
                    need_gutter = false;
                }

                const logical_idx = if (p_idx == 0) c_idx else view.buf.gap_start + c_idx;

                if (c == '\n') {
                    if (current_row > view.row_offset) {
                        self.clearLineTail(buf, view, current_col, screen_row, text_width);
                        screen_row += 1;
                        need_gutter = true;

                        const ghosts_drawn = drawGhostsAtRow(buf, editor, current_row - 1, screen_row, max_rows);
                        screen_row +|= ghosts_drawn;
                    }
                    current_row += 1;
                    current_col = 1;
                } else if (c == '\t') {
                    if (current_row > view.row_offset) {
                        var tab_col = current_col;
                        for (0..TAB_SIZE) |_| {
                            if (tab_col > view.col_offset and tab_col <= view.col_offset + text_width) {
                                const zx = view.x - 1 + view.gutter_width + (tab_col - view.col_offset - 1);
                                const zy = screen_row - 1;
                                const tab_style = styleAt(view.buf, logical_idx);
                                buf.setCell(@intCast(zx), @intCast(zy), " ", tab_style);
                            }
                            tab_col += 1;
                        }
                    }
                    current_col += 4;
                } else {
                    const is_continuation_byte = (c & 0xC0) == 0x80;
                    const eval_col = if (is_continuation_byte) current_col - 1 else current_col;

                    if (current_row > view.row_offset) {
                        if (eval_col > view.col_offset and eval_col <= view.col_offset + text_width) {
                            const target_style = styleAt(view.buf, logical_idx);
                            if (!std.meta.eql(current_style, target_style)) {
                                current_style = target_style;
                            }

                            // Write a full UTF-8 codepoint so multi-byte
                            // characters occupy a single cell.
                            var scratch: [4]u8 = undefined;
                            const glyph = readCodepoint(view.buf, logical_idx, &scratch);

                            const zx = view.x - 1 + view.gutter_width + (eval_col - view.col_offset - 1);
                            const zy = screen_row - 1;
                            buf.setCell(@intCast(zx), @intCast(zy), glyph, target_style);
                        }
                    }
                    if (!is_continuation_byte) {
                        current_col += 1;
                    }
                }
            }
        }

        if (screen_row <= max_rows) {
            if (need_gutter and current_row > view.row_offset) {
                self.drawGutter(buf, view, current_row, screen_row);
                need_gutter = false;
            }
            self.clearLineTail(buf, view, current_col, screen_row, text_width);
            screen_row += 1;
        }

        // Tilde lines for empty rows below the content.
        while (screen_row <= max_rows) : (screen_row += 1) {
            self.drawTildeRow(buf, view, screen_row, text_width);
        }

        view.is_dirty = false;
    }

    /// Reads a full UTF-8 codepoint from the logical buffer starting at
    /// `logical_idx`, writing the bytes into `scratch`. Returns a slice of `scratch`.
    fn readCodepoint(gap: anytype, logical_idx: usize, scratch: *[4]u8) []const u8 {
        const lead = gap.charAt(logical_idx) orelse return " ";
        const len = utf8Length(lead);
        var n: usize = 0;
        while (n < len) : (n += 1) {
            scratch[n] = gap.charAt(logical_idx + n) orelse ' ';
        }
        return scratch[0..len];
    }

    /// Resolves the highest-priority extmark style covering `logical_idx`.
    fn styleAt(gap: anytype, logical_idx: usize) zui.Style {
        var target: ?zui.Style = null;
        var current_priority: i32 = -1;
        var i: usize = gap.extmarks.items.len;
        while (i > 0) {
            i -= 1;
            const mark = gap.extmarks.items[i];
            if (logical_idx >= mark.logical_start and logical_idx < mark.logical_end) {
                if (@as(i32, mark.priority) >= current_priority) {
                    target = mark.style;
                    current_priority = mark.priority;
                }
            }
        }
        return target orelse .{};
    }

    /// Clears (pads with spaces) the remainder of a line after the content.
    fn clearLineTail(self: *Renderer, buf: *zui.Buffer, view: *View, pad_col: usize, screen_row: u16, text_width: u16) void {
        _ = self;
        if (screen_row == 0 or screen_row > buf.height) return;

        var col = pad_col;
        if (col <= view.col_offset) col = view.col_offset + 1;

        const zy = screen_row - 1;
        while (col <= view.col_offset + text_width) : (col += 1) {
            const zx = view.x - 1 + view.gutter_width + (col - view.col_offset - 1);
            buf.setCell(@intCast(zx), @intCast(zy), " ", .{});
        }
    }

    /// Draws the gutter (line number) for a row.
    fn drawGutter(self: *Renderer, buf: *zui.Buffer, view: *View, row: usize, screen_row: u16) void {
        _ = self;
        if (screen_row == 0 or screen_row > buf.height) return;

        const zy = screen_row - 1;
        const gutter_start = view.x - 1;

        const current_cursor_row = view.buf.getCursorPos().y;
        const is_current = (row == current_cursor_row);
        const style = if (is_current)
            zui.Style{ .fg = .Magenta }
        else
            zui.Style{ .fg = .{ .ANSI = 240 } };

        var num_buf: [16]u8 = undefined;
        const num_str = std.fmt.bufPrint(&num_buf, "{d}", .{row}) catch return;

        const required_space = num_str.len + 1;
        const padding = if (view.gutter_width > required_space)
            @as(u16, @intCast(view.gutter_width - required_space))
        else
            0;

        var x: u16 = padding;
        buf.setString(gutter_start + x, zy, num_str, style);
        x +|= @intCast(num_str.len);
        if (x < view.gutter_width) {
            buf.setCell(gutter_start + x, zy, " ", .{});
        }
    }

    /// Draws the ghost lines that belong to `buffer_row` after its content row.
    fn drawGhostsAtRow(buf: *zui.Buffer, editor: *Editor, buffer_row: usize, screen_y: u16, max_rows: u16) u16 {
        var lines_drawn: u16 = 0;
        if (editor.ghost_manager.ghosts.items.len == 0) return lines_drawn;

        for (editor.ghost_manager.ghosts.items) |ghost| {
            if (ghost.buffer_row != buffer_row) continue;

            const target_y = screen_y + lines_drawn;
            if (target_y > max_rows) break;

            const zy = target_y - 1;
            if (zy >= buf.height) break;

            const view = editor.getActiveView();
            const start_x = view.x - 1 + view.gutter_width + @as(u16, @intCast(ghost.col_offset));
            var x = start_x;

            if (ghost.prefix) |p| {
                const remaining = if (x < buf.width) buf.width - x else 0;
                if (remaining > 0) {
                    const max_bytes = @min(p.len, remaining);
                    buf.setString(x, zy, p[0..max_bytes], ghost.theme);
                    x += @intCast(max_bytes);
                }
            }
            if (x < buf.width) {
                const remaining = buf.width - x;
                const max_bytes = @min(ghost.text.len, remaining);
                buf.setString(x, zy, ghost.text[0..max_bytes], ghost.theme);
            }
            lines_drawn += 1;
        }
        return lines_drawn;
    }

    /// Draws a tilde row for content-free lines below the buffer.
    fn drawTildeRow(self: *Renderer, buf: *zui.Buffer, view: *View, screen_row: u16, text_width: u16) void {
        _ = self;
        if (screen_row == 0 or screen_row > buf.height) return;
        const zy = screen_row - 1;

        const tilde_style = zui.Style{ .fg = .{ .ANSI = 240 } };

        // Place "~" where the gutter ends, then fill the rest with spaces.
        const req_space: u16 = 2;
        const padding = if (view.gutter_width > req_space) @as(u16, @intCast(view.gutter_width - req_space)) else 0;

        var x: u16 = view.x - 1 + padding;
        buf.setCell(x, zy, "~", tilde_style);
        x += 1;
        if (x < buf.width) buf.setCell(x, zy, " ", tilde_style);
        x += 1;

        var i: u16 = 0;
        while (i < text_width) : (i += 1) {
            buf.setCell(x + i, zy, " ", .{});
        }
    }

    // ==========================================
    // BORDERS & OVERLAYS
    // ==========================================

    /// Draws split-pane borders between multiple views.
    fn traceBorder(self: *Renderer, buf: *zui.Buffer, editor: *Editor) void {
        _ = self;
        if (editor.views.items.len <= 1) return;

        const border_style = zui.Style{ .fg = .{ .ANSI = 240 } };

        for (editor.views.items) |view| {
            // Horizontal separator above a view.
            if (view.y > 1) {
                const y = view.y - 1 - 1;
                var x: u16 = view.x - 1;
                for (0..view.width) |_| {
                    buf.setCell(x, y, "─", border_style);
                    x += 1;
                }
            }
            // Vertical separator to the left of a view.
            if (view.x > 1) {
                const border_x = view.x - 1 - 1;
                var y: u16 = view.y - 1;
                for (0..view.height) |_| {
                    buf.setCell(border_x, y, "│", border_style);
                    y += 1;
                }
            }
            // Crossing point.
            if (view.y > 1 and view.x > 1) {
                buf.setCell(view.x - 1 - 1, view.y - 1 - 1, "┼", border_style);
            }
        }
    }

    fn renderPopups(self: *Renderer, buf: *zui.Buffer, editor: *Editor) void {
        var it = editor.pop_store.valueIterator();
        while (it.next()) |pop| {
            self.drawPop(buf, pop);
        }
    }

    /// Draws a Pop window with a box-drawing border and centered text.
    fn drawPop(self: *Renderer, buf: *zui.Buffer, pop: *const @import("pop.zig").Pop) void {
        _ = self;
        const x0: u16 = @intCast(pop.pos.x - 1);
        const y0: u16 = @intCast(pop.pos.y - 1);
        const w: u16 = @intCast(pop.size.x);
        const h: u16 = @intCast(pop.size.y);

        const border_style = zui.Style{ .fg = .White };
        const inner_style = zui.Style{ .fg = .White };

        // Top border
        buf.setCell(x0, y0, "┌", border_style);
        for (1..w - 1) |k| {
            buf.setCell(x0 + @as(u16, @intCast(k)), y0, "─", border_style);
        }
        if (w >= 2) buf.setCell(x0 + w - 1, y0, "┐", border_style);

        // Sides + blank interior.
        var i: u16 = 1;
        while (i < h - 1) : (i += 1) {
            buf.setCell(x0, y0 + i, "│", border_style);
            var j: u16 = 1;
            while (j < w - 1) : (j += 1) {
                buf.setCell(x0 + j, y0 + i, " ", inner_style);
            }
            if (w >= 2) buf.setCell(x0 + w - 1, y0 + i, "│", border_style);
        }

        // Bottom border
        buf.setCell(x0, y0 + h - 1, "└", border_style);
        for (1..w - 1) |k| {
            buf.setCell(x0 + @as(u16, @intCast(k)), y0 + h - 1, "─", border_style);
        }
        if (w >= 2) buf.setCell(x0 + w - 1, y0 + h - 1, "┘", border_style);

        // Centered text lines.
        var lines = std.mem.splitScalar(u8, pop.buffer.items, '\n');
        var row_offset: u16 = 1;
        const inner_w = w - 2;
        const max_text_h = h - 2;

        while (lines.next()) |line| {
            if (row_offset >= max_text_h) break;

            const display_len = @min(line.len, inner_w);
            const left_padding = (inner_w - @as(u16, @intCast(display_len))) / 2;
            const start_x = x0 + 1 + left_padding;
            const text_y = y0 + row_offset;

            if (text_y < buf.height and start_x < buf.width) {
                buf.setString(start_x, text_y, line[0..display_len], inner_style);
            }
            row_offset += 1;
        }
    }

    fn renderToasts(self: *Renderer, buf: *zui.Buffer, editor: *Editor) void {
        _ = self;
        if (editor.toast_manager.toasts.items.len == 0) return;

        const buf_width = buf.width;
        const buf_height = buf.height;
        if (buf_height == 0 or buf_width == 0) return;

        var offset_y: u16 = 1;

        var i: usize = editor.toast_manager.toasts.items.len;
        while (i > 0) {
            i -= 1;
            const toast = editor.toast_manager.toasts.items[i];

            const display_len: u16 = @intCast(toast.text.len + 4);
            const x = if (buf_width > display_len) buf_width - display_len else 1;
            const y = if (buf_height > offset_y) buf_height - offset_y else 1;

            if (y < buf_height) {
                buf.setString(x, y, toast.text, toast.theme);
            }
            offset_y += 1;
        }
    }

    fn renderPum(self: *Renderer, buf: *zui.Buffer, editor: *Editor) void {
        _ = self;
        if (!editor.pum.active or editor.pum.items.items.len == 0) return;

        var max_bytes: usize = 0;
        for (editor.pum.items.items) |item| {
            var current_bytes: usize = item.text.len;
            if (item.icon) |icon| current_bytes += icon.len + 1;
            if (current_bytes > max_bytes) max_bytes = current_bytes;
        }

        var current_y: i32 = @as(i32, editor.pum.y) - 1;

        for (editor.pum.items.items, 0..) |item, idx| {
            if (current_y <= 0) break;
            const zy = @as(u16, @intCast(current_y)) - 1;
            if (zy >= buf.height) break;

            const is_selected = (idx == editor.pum.selected_idx);
            const theme = if (is_selected)
                zui.Style{ .fg = .Black, .bg = .White, .add_modifier = .{ .bold = true } }
            else
                zui.Style{ .fg = .White, .bg = .Black };

            const total_len = max_bytes + 1;
            var line_buf: [4096]u8 = undefined;
            if (total_len > line_buf.len) break;

            var cursor: usize = 0;
            line_buf[cursor] = ' ';
            cursor += 1;

            if (item.icon) |icon| {
                const icon_style = if (is_selected) theme else zui.Style{ .fg = .White, .bg = .Black };
                const x0 = editor.pum.x;
                if (x0 < buf.width) {
                    buf.setString(x0 + @as(u16, @intCast(cursor)), zy, icon, if (item.icon_color != null) icon_style else icon_style);
                }
                cursor += icon.len + 1;
            }

            const text_x = editor.pum.x + @as(u16, @intCast(cursor));
            if (text_x < buf.width) {
                buf.setString(text_x, zy, item.text, theme);
            }

            current_y -= 1;
        }
    }
};

fn utf8Length(lead: u8) usize {
    if (lead < 0x80) return 1;
    if ((lead & 0xe0) == 0xc0) return 2;
    if ((lead & 0xf0) == 0xe0) return 3;
    if ((lead & 0xf8) == 0xf0) return 4;
    return 1;
}
