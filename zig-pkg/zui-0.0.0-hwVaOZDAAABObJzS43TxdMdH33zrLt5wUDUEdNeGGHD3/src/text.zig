//! This module defines the core text rendering primitives.
//!
//! Text in Zui is broken down into a hierarchy to allow fine-grained styling:
//! - `Span`: A contiguous string slice with a single unified `Style`.
//! - `Line`: A sequence of `Span`s, representing a single horizontal line of text.
//! - `Text`: A sequence of `Line`s, representing a multi-line paragraph.

const std = @import("std");
const Style = @import("style.zig").Style;

pub const Span = struct {
    const Self = @This();

    content: []const u8,
    style: Style,

    /// Creates a new `Span` with the default empty style.
    pub fn raw(content: []const u8) Self {
        return .{
            .content = content,
            .style = .init(),
        };
    }

    /// Creates a new `Span` with a specific style.
    pub fn styled(content: []const u8, style: Style) Self {
        return .{
            .content = content,
            .style = style,
        };
    }

    /// Patches the span's current style with another style.
    pub fn patchStyle(self: Self, other: Style) Self {
        var new = self;
        new.style = self.style.patch(other);
        return new;
    }

    /// Calculates the visible width of the span?
    /// NOTE: UTF-8 codepoint counting to correctly size accented characters.
    /// Note: This does not account for double-width characters (like emojis or Kanjis).
    pub fn width(self: Self) usize {
        return std.unicode.utf8CountCodepoints(self.content) catch self.content.len;
    }
};

pub const Line = struct {
    const Self = @This();

    spans: []const Span,

    pub fn init(spans: []const Span) Self {
        return .{
            .spans = spans,
        };
    }

    pub fn width(self: Self) usize {
        var total: usize = 0;
        for (self.spans) |span| {
            total += span.width();
        }
        return total;
    }

    pub fn patchStyle(self: Self, allocator: std.mem.Allocator, style: Style) !Self {
        var new_spans = try allocator.alloc(Span, self.spans.len);

        for (self.spans, 0..) |span, i| {
            new_spans[i] = span.patchStyle(style);
        }

        return Self{ .spans = new_spans };
    }
};

pub const Text = struct {
    const Self = @This();

    lines: []const Line,

    /// Creates a new `Text` from a slice of `Line`s.
    pub fn init(lines: []const Line) Self {
        return .{
            .lines = lines,
        };
    }

    /// Calculates the maximum width among all lines.
    /// This is useful for layout calculations (e.g. finding the widest line in a block).
    pub fn width(self: Self) usize {
        var max_w: usize = 0;
        for (self.lines) |line| {
            const w = line.width();
            if (w > max_w) {
                max_w = w;
            }
        }

        return max_w;
    }

    /// Calculates the height of the text (number of lines).
    pub fn height(self: Self) usize {
        return self.lines.len;
    }

    pub fn patchStyle(self: Self, allocator: std.mem.Allocator, style: Style) !Self {
        var new_lines = try allocator.alloc(Line, self.lines.len);

        for (self.lines, 0..) |line, i| {
            new_lines[i] = try line.patchStyle(allocator, style);
        }

        return Self{ .lines = new_lines };
    }
};

test "Span creation and width" {
    const span1 = Span.raw("Hello");
    try std.testing.expectEqualStrings("Hello", span1.content);
    try std.testing.expectEqual(@as(usize, 5), span1.width());

    const styled_span = Span.styled("World", Style.init().wfg(.Red));
    try std.testing.expectEqualStrings("World", styled_span.content);
}

test "Line width calculation" {
    const spans = [_]Span{
        Span.raw("Hello, "),
        Span.styled("Zui", Style.init().a_bold()),
        Span.raw("!"),
    };

    const line = Line.init(&spans);

    // "Hello, " (7) + "Zui" (3) + "!" (1) = 11
    try std.testing.expectEqual(@as(usize, 11), line.width());
}

test "Text dimensions" {
    const l1_spans = [_]Span{Span.raw("Hello")};
    const l2_spans = [_]Span{Span.styled("World!", Style.init().a_bold())};

    const lines = [_]Line{
        Line.init(&l1_spans),
        Line.init(&l2_spans),
    };

    const text = Text.init(&lines);

    try std.testing.expectEqual(@as(usize, 6), text.width()); // "World!" is the longest (6)
    try std.testing.expectEqual(@as(usize, 2), text.height()); // 2 lines
}
