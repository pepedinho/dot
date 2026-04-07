const std = @import("std");
const buffer = @import("../core/gap.zig");
const Editor = @import("../core/core.zig").Editor;
const View = @import("../core/pane.zig").View;
const style = @import("style.zig");
const ansi = @import("ansi.zig");
const pop = @import("pop.zig");

const MODE = [_][]const u8{ "NORMAL", "INSERT", "COMMAND", "SEARCH" };

pub const AnimatedRegion = struct {
    x: usize,
    y: usize,
    span: style.Span,
};

/// The standalone Rendering Engine.
/// Manages animation states, transient memory (Arena), and visual output.
pub const Renderer = struct {
    allocator: std.mem.Allocator,
    animation_phase: f32 = 0.0,
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

        self.animation_phase += 0.5; // Animation speed
        if (self.animation_phase > 1000.0) self.animation_phase = 0.0;

        return true;
    }

    // ==========================================
    // CORE RENDERING PIPELINE
    // ==========================================

    /// Speed 1: Full Screen Redraw
    pub fn refreshScreen(self: *Renderer, editor: *Editor, stdout: anytype) !void {
        self.active_animations.clearRetainingCapacity();
        try stdout.writeAll(ansi.hide_cursor);
        try stdout.writeAll(ansi.clear_screen);

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const frame_alloc = arena.allocator();

        for (editor.views.items) |*view| {
            try self.renderView(stdout, view); // TODO: Later, pass frame_alloc for syntax highlighting
        }

        try self.traceBorder(stdout, editor);
        try self.displayMode(stdout, editor, frame_alloc);
        try editor.renderAllPopup(stdout);
        try self.placeCursor(stdout, editor, frame_alloc);

        try stdout.writeAll(ansi.show_cursor);
    }

    /// Speed 2: Targeted Redraw (Dirty Rectangles & Animations)
    pub fn refreshDirtyViews(self: *Renderer, editor: *Editor, stdout: anytype) !void {
        self.active_animations.clearRetainingCapacity();
        try stdout.writeAll(ansi.hide_cursor);

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const frame_alloc = arena.allocator();

        for (editor.views.items) |*view| {
            if (view.is_dirty) {
                try self.renderView(stdout, view);
            }
        }

        try self.traceBorder(stdout, editor);
        try self.displayMode(stdout, editor, frame_alloc);
        try editor.renderAllPopup(stdout);
        try self.placeCursor(stdout, editor, frame_alloc);

        try stdout.writeAll(ansi.show_cursor);
    }

    /// Speed 3: Micro Redraw (Active Line Only)
    pub fn updateCurrentLine(self: *Renderer, editor: *Editor, stdout: anytype) !void {
        if (editor.mode == .Command) return;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        // const frame_alloc = arena.allocator(); // Ready for syntax highlighting

        const view = editor.getActiveView();
        const buf = view.buf;
        const pos = buf.getCursorPos();

        const screen_y = view.y + pos.y - view.row_offset - 1;
        const screen_x = view.x + pos.x - view.col_offset - 1;

        try stdout.writeAll(ansi.hide_cursor);
        try ansi.goto(stdout, screen_y, view.x);

        var start_of_line = buf.gap_start;
        while (start_of_line > 0 and buf.buffer[start_of_line - 1] != '\n') {
            start_of_line -= 1;
        }

        var end_of_line = buf.gap_end;
        while (end_of_line < buf.buffer.len and buf.buffer[end_of_line] != '\n') {
            end_of_line += 1;
        }

        var current_col: usize = 1;
        var drawn_chars: usize = 0;
        const parts = [_][]const u8{ buf.buffer[start_of_line..buf.gap_start], buf.buffer[buf.gap_end..end_of_line] };

        for (parts) |part| {
            for (part) |c| {
                if (c == '\t') {
                    const TAB_SIZE = 8;
                    for (0..TAB_SIZE) |_| {
                        if (current_col > view.col_offset and current_col <= view.col_offset + view.width) {
                            try stdout.writeAll(" ");
                            drawn_chars += 1;
                        }
                        current_col += 1;
                    }
                } else {
                    if (current_col > view.col_offset and current_col <= view.col_offset + view.width) {
                        try stdout.writeAll(&[_]u8{c});
                        drawn_chars += 1;
                    }
                    current_col += 1;
                }
            }
        }

        while (drawn_chars < view.width) : (drawn_chars += 1) {
            try stdout.writeAll(" ");
        }

        // Handle Z-Index popups
        var it = editor.pop_store.valueIterator();
        while (it.next()) |p| {
            const pop_top = p.pos.y;
            const pop_bottom = p.pos.y + p.size.y - 1;
            if (screen_y >= pop_top and screen_y <= pop_bottom) {
                try pop.render(stdout, p);
            }
        }

        try ansi.goto(stdout, screen_y, screen_x);
        try stdout.writeAll(ansi.show_cursor);
    }

    /// Rendering Speed 4: Animations Only.
    /// Draws ONLY the registered animated regions using their stored Spans.
    pub fn refreshAnimationsOnly(self: *Renderer, stdout: anytype, editor: *Editor) !void {
        try stdout.writeAll(ansi.hide_cursor);

        for (self.active_animations.items) |anim| {
            try ansi.goto(stdout, anim.y, anim.x);

            try anim.span.render(stdout, self.animation_phase);

            try stdout.writeAll("\x1b[0m");
        }

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        try self.placeCursor(stdout, editor, arena.allocator());

        try stdout.writeAll(ansi.show_cursor);
    }

    // ==========================================
    // RETAINED MODE UI COMPONENTS
    // ==========================================

    /// Renders the Status Line using the Line -> Span architecture with Arena Allocator
    fn displayMode(self: *Renderer, stdout: anytype, editor: *Editor, arena: std.mem.Allocator) !void {
        const win = editor.win;
        try stdout.print("\x1b[{d};1H\x1b[2K", .{win.rows});

        var status_line = style.Line.init(arena);

        const mode_bg = switch (editor.mode) {
            .Normal => style.Color.Cyan,
            .Insert => style.Color.Green,
            .Command => style.Color.Red,
            .Search => style.Color.Yellow,
        };

        const mode_idx = @intFromEnum(editor.mode);
        try status_line.addSpan(style.Span.init(MODE[mode_idx], .{ .bg = mode_bg, .fg = .Black, .bold = true }));
        try status_line.addText(" | ");

        const mode_str_len = MODE[mode_idx].len;
        const filename_x = mode_str_len + 3 + 1;

        const buf_idx = editor.getCurrentBufferIdx();
        if (editor.buffers.items[buf_idx].filename) |f| {
            const shimmer_opts = ansi.ShimmerOptions{
                .base_color = .{ .r = 100, .g = 100, .b = 100 }, //grey
                .highlight_color = .{ .r = 255, .g = 215, .b = 0 },
                .wave_width = 6.0,
            };

            const f_span = style.Span.init(f, .{ .effect = .{ .Shimmer = shimmer_opts }, .bold = true });
            // THE SHIMMER EFFECT TEST: We assign the Shimmer effect to the filename!
            try status_line.addSpan(f_span);
            try self.active_animations.append(self.allocator, .{
                .x = filename_x,
                .y = win.rows,
                .span = f_span,
            });
        } else {
            try status_line.addSpan(style.Span.init("[No Name]", .{ .italic = true, .fg = .White }));
        }

        // Fill the rest of the status line with a background color
        try status_line.addText(" ");
        try status_line.render(stdout, self.animation_phase);
    }

    fn commandPrompt(self: *Renderer, stdout: anytype, editor: *Editor, arena: std.mem.Allocator) !void {
        _ = self;
        const row = editor.win.rows;
        const text = editor.cmd_buf.items;
        const cols = editor.win.cols;

        const mode_str = MODE[@intFromEnum(editor.mode)];
        const offset = mode_str.len + 3;
        try ansi.goto(stdout, row, offset + 1);

        // try stdout.print("\x1b[{d};1H", .{row});
        const prompt_char = if (editor.mode == .Search) "/" else ":";
        var cmd_line = style.Line.init(arena);

        try cmd_line.addSpan(style.Span.init(prompt_char, .{ .bg = .Black, .fg = .Yellow, .bold = true }));
        try cmd_line.addSpan(style.Span.init(text, .{ .bg = .Black, .fg = .White }));

        const used_cols = offset + text.len + 1;
        if (cols > used_cols) {
            const padding = try arena.alloc(u8, cols - used_cols);
            @memset(padding, ' ');
            try cmd_line.addSpan(style.Span.init(padding, .{ .bg = .Black }));
        }

        try cmd_line.render(stdout, 0.0);
        try ansi.goto(stdout, row, used_cols + 1);
    }

    // ==========================================
    // UTILS & LEGACY DRAWING
    // ==========================================

    fn placeCursor(self: *Renderer, stdout: anytype, editor: *Editor, arena: std.mem.Allocator) !void {
        if (editor.mode == .Command or editor.mode == .Search) {
            try self.commandPrompt(stdout, editor, arena);
        } else {
            const view = editor.getActiveView();
            const pos = view.buf.getCursorPos();
            const screen_y = view.y + pos.y - view.row_offset - 1;
            const screen_x = view.x + pos.x - view.col_offset - 1;
            try ansi.goto(stdout, screen_y, screen_x);
        }
    }

    fn renderView(self: *Renderer, stdout: anytype, view: *View) !void {
        _ = self;
        const part1 = view.buf.getFirst();
        const part2 = view.buf.getSecond();

        var current_row: usize = 1;
        var current_col: usize = 1;

        var screen_row = view.y;
        const max_rows = view.y + view.height - 1;
        const clear_to_eol = "\x1b[K";

        try ansi.goto(stdout, screen_row, view.x);

        const parts = [_][]const u8{ part1, part2 };
        for (parts, 0..) |part, p_idx| {
            for (part, 0..) |c, c_idx| {
                if (screen_row > max_rows) break;

                const physical_idx = if (p_idx == 0) c_idx else view.buf.gap_end + c_idx;

                var is_highlighted = false;
                for (view.buf.highlight.items) |mark| {
                    if (physical_idx >= mark.start and physical_idx < mark.end) {
                        is_highlighted = true;
                        break;
                    }
                }

                if (c == '\n') {
                    if (current_row > view.row_offset) {
                        try stdout.writeAll(clear_to_eol);
                        screen_row += 1;
                        if (screen_row <= max_rows) {
                            try ansi.goto(stdout, screen_row, view.x);
                        }
                    }
                    current_row += 1;
                    current_col = 1;
                } else if (c == '\t') {
                    const TAB_SIZE = 8;
                    for (0..TAB_SIZE) |_| {
                        if (current_row > view.row_offset) {
                            if (current_col > view.col_offset and current_col <= view.col_offset + view.width) {
                                try stdout.writeAll(" ");
                            }
                        }
                        current_col += 1;
                    }
                } else {
                    if (current_row > view.row_offset) {
                        if (current_col > view.col_offset and current_col <= view.col_offset + view.width) {
                            if (is_highlighted) try stdout.writeAll("\x1b[43;30m");
                            try stdout.writeAll(&[_]u8{c});
                            if (is_highlighted) try stdout.writeAll("\x1b[m");
                        }
                    }
                    current_col += 1;
                }
            }
        }

        if (screen_row <= max_rows) {
            try stdout.writeAll(clear_to_eol);
            screen_row += 1;
        }

        while (screen_row <= max_rows) : (screen_row += 1) {
            try ansi.goto(stdout, screen_row, view.x);
            try stdout.writeAll(clear_to_eol);
        }

        view.is_dirty = false;
    }

    fn traceBorder(self: *Renderer, stdout: anytype, editor: *Editor) !void {
        _ = self;
        if (editor.views.items.len > 1) {
            try stdout.writeAll("\x1b[38;5;240m");
            for (editor.views.items) |view| {
                if (view.y > 1) {
                    try ansi.goto(stdout, view.y - 1, view.x);
                    for (0..view.width) |_| {
                        try stdout.writeAll("─");
                    }
                }
                if (view.x > 1) {
                    for (0..view.height) |h| {
                        try ansi.goto(stdout, view.y + h, view.x - 1);
                        try stdout.writeAll("│");
                    }
                }
                if (view.y > 1 and view.x > 1) {
                    try ansi.goto(stdout, view.y - 1, view.x - 1);
                    try stdout.writeAll("┼");
                }
            }
            try stdout.writeAll("\x1b[0m");
        }
    }
};
