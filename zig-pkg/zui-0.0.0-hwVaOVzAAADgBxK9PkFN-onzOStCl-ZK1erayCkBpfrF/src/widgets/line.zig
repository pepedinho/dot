const Style = @import("../style.zig").Style;
const Span = @import("span.zig").Span;

pub const Line = struct {
    spans: []const Span,

    pub fn fromStr(text: []const u8, style: Style) Line {
        return .{ .spans = .{
            .text = text,
            .style = style,
        } };
    }
};
