//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const style_mod = @import("style.zig");
const text_mod = @import("text.zig");
const buffer_mod = @import("buffer.zig");
const layout_mod = @import("layout.zig");
const terminal_mod = @import("terminal.zig");

pub const backend = struct {
    pub const ansi = @import("backend/ansi.zig");
};

pub const widgets = struct {
    pub const Block = @import("widgets/block.zig").Block;
    pub const Borders = @import("widgets/block.zig").Borders;
    pub const Paragraph = @import("widgets/paragraph.zig").Paragraph;
    pub const List = @import("widgets/list.zig").List;
    pub const Span = @import("widgets/span.zig").Span;
    pub const Line = @import("widgets/line.zig").Line;
    pub const Gauge = @import("widgets/gauge.zig").Gauge;
    pub const Clear = @import("widgets/clear.zig").Clear;
};

pub const style = style_mod;
pub const Color = style_mod.Color;
pub const Modifier = style_mod.Modifier;
pub const Style = style_mod.Style;
pub const text = text_mod;
pub const Span = text_mod.Span;
pub const Line = text_mod.Line;
pub const buffer = buffer_mod;
pub const Cell = buffer_mod.Cell;
pub const Buffer = buffer_mod.Buffer;
pub const layout = layout_mod;
pub const Rect = layout.Rect;
pub const Layout = layout.Layout;
pub const Constraint = layout.Constraint;
pub const terminal = terminal_mod;

test {
    std.testing.refAllDecls(@This());
}
