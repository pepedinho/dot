const std = @import("std");
const buffer = @import("../core/gap.zig");
const Editor = @import("../core/core.zig").Editor;
const View = @import("../core/pane.zig").View;
const style = @import("style.zig");
const ansi = @import("ansi.zig");
const pop = @import("pop.zig");

const MODE = [_][]const u8{ "NORMAL", "INSERT", "COMMAND", "SEARCH" };
const TAB_SIZE = 4;

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
            try self.renderView(stdout, editor, view); // TODO: Later, pass frame_alloc for syntax highlighting
        }

        try self.traceBorder(stdout, editor);
        try self.displayMode(stdout, editor, frame_alloc);
        try editor.renderAllPopup(stdout);

        try editor.toast_manager.render(stdout, editor.win.cols, editor.win.rows);
        try editor.pum.render(stdout);

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
                try self.renderView(stdout, editor, view);
            }
        }

        try self.traceBorder(stdout, editor);
        try self.displayMode(stdout, editor, frame_alloc);
        try editor.renderAllPopup(stdout);

        try editor.toast_manager.render(stdout, editor.win.cols, editor.win.rows);
        try editor.pum.render(stdout);
        try self.placeCursor(stdout, editor, frame_alloc);

        try stdout.writeAll(ansi.show_cursor);
    }

    /// Speed 3: Micro Redraw (Active Line Only)
    pub fn updateCurrentLine(self: *Renderer, editor: *Editor, stdout: anytype) !void {
        if (editor.mode == .Command) return;

        const view = editor.getActiveView();
        view.is_dirty = true;
        try self.refreshDirtyViews(editor, stdout);
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
            .Normal => ansi.Cyan,
            .Insert => ansi.Green,
            .Command => ansi.Red,
            .Search => ansi.Yellow,
        };

        const mode_idx = @intFromEnum(editor.mode);
        try status_line.addSpan(style.Span.init(MODE[mode_idx], .{ .bg = mode_bg, .fg = ansi.Black, .bold = true }));
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
            try status_line.addSpan(style.Span.init("[No Name]", .{ .italic = true, .fg = ansi.White }));
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

        try cmd_line.addSpan(style.Span.init(prompt_char, .{ .bg = ansi.Black, .fg = ansi.Yellow, .bold = true }));
        try cmd_line.addSpan(style.Span.init(text, .{ .bg = ansi.Black, .fg = ansi.White }));

        const used_cols = offset + text.len + 1;
        if (cols > used_cols) {
            const padding = try arena.alloc(u8, cols - used_cols);
            @memset(padding, ' ');
            try cmd_line.addSpan(style.Span.init(padding, .{ .bg = ansi.Black }));
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
            var layout_shift: usize = 0;
            for (editor.ghost_manager.ghosts.items) |g| {
                if (g.buffer_row < pos.y - 1) {
                    layout_shift += 1;
                }
            }
            const screen_y = view.y + pos.y - view.row_offset - 1 + layout_shift;
            const screen_x = view.x + view.gutter_width + pos.x - view.col_offset - 1;
            try ansi.goto(stdout, screen_y, screen_x);
        }
    }

    fn renderView(self: *Renderer, stdout: anytype, editor: *Editor, view: *View) !void {
        _ = self;
        const part1 = view.buf.getFirst();
        const part2 = view.buf.getSecond();

        var current_row: usize = 1;
        var current_col: usize = 1;

        var screen_row = view.y;
        const max_rows = view.y + view.height - 1;

        const text_width = view.width - view.gutter_width;
        var need_gutter = true;

        try ansi.goto(stdout, screen_row, view.x + view.gutter_width);

        const parts = [_][]const u8{ part1, part2 };
        for (parts, 0..) |part, p_idx| {
            for (part, 0..) |c, c_idx| {
                if (screen_row > max_rows) break;

                if (need_gutter and current_row > view.row_offset) {
                    try ansi.goto(stdout, screen_row, view.x);
                    try stdout.writeAll("\x1b[90m"); // TODO: make style dynamic & scriptable by lua api
                    var num_buf: [16]u8 = undefined;
                    const num_str = std.fmt.bufPrint(&num_buf, "{d}", .{current_row}) catch "err";

                    const required_space = num_str.len + 1;

                    const padding = if (view.gutter_width > required_space)
                        view.gutter_width - required_space
                    else
                        0;

                    for (0..padding) |_| {
                        try stdout.writeAll(" ");
                    }

                    try stdout.writeAll(num_str);
                    try stdout.writeAll(" ");

                    try stdout.writeAll("\x1b[0m");
                    try ansi.goto(stdout, screen_row, view.x + view.gutter_width);
                    need_gutter = false;
                }

                const logical_idx = if (p_idx == 0) c_idx else view.buf.gap_start + c_idx;

                // var is_highlighted = false;
                var active_style: ?style.Style = null;
                for (view.buf.extmarks.items) |mark| {
                    if (logical_idx >= mark.logical_start and logical_idx < mark.logical_end) {
                        active_style = mark.style;
                        break;
                    }
                }

                if (c == '\n') {
                    if (current_row > view.row_offset) {
                        var pad_col = current_col;
                        if (pad_col <= view.col_offset) pad_col = view.col_offset + 1;

                        while (pad_col <= view.col_offset + text_width) : (pad_col += 1) {
                            try stdout.writeAll(" ");
                        }
                        screen_row += 1;
                        need_gutter = true;

                        const ghosts_drawn = try editor.ghost_manager.renderAtRow(stdout, current_row - 1, @as(u16, @intCast(view.x + view.gutter_width)), @as(u16, @intCast(screen_row)), @as(u16, @intCast(max_rows)));

                        screen_row += ghosts_drawn;

                        if (screen_row <= max_rows) {
                            try ansi.goto(stdout, screen_row, view.x);
                        }
                    }
                    current_row += 1;
                    current_col = 1;
                } else if (c == '\t') {
                    for (0..TAB_SIZE) |_| {
                        if (current_row > view.row_offset) {
                            if (current_col > view.col_offset and current_col <= view.col_offset + text_width) {
                                try stdout.writeAll(" ");
                            }
                        }
                        current_col += 1;
                    }
                } else {
                    if (current_row > view.row_offset) {
                        if (current_col > view.col_offset and current_col <= view.col_offset + text_width) {
                            if (active_style) |s| try s.toAnsi(stdout);
                            try stdout.writeAll(&[_]u8{c});
                            if (active_style != null) try stdout.writeAll("\x1b[m");
                        }
                    }
                    current_col += 1;
                }
            }
        }

        if (screen_row <= max_rows) {
            var pad_col = current_col;
            if (pad_col <= view.col_offset) pad_col = view.col_offset + 1;

            while (pad_col <= view.col_offset + text_width) : (pad_col += 1) {
                try stdout.writeAll(" ");
            }
            screen_row += 1;
        }

        while (screen_row <= max_rows) : (screen_row += 1) {
            try ansi.goto(stdout, screen_row, view.x);
            try stdout.writeAll("\x1b[90m  ~ \x1b[0m");
            for (0..view.width) |_| {
                try stdout.writeAll(" ");
            }
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
