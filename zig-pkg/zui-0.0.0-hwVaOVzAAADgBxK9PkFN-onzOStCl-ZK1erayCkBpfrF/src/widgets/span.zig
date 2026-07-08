const Style = @import("../style.zig").Style;

pub const Span = struct {
    text: []const u8,
    style: Style = .{},
};
