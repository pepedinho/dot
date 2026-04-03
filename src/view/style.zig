const std = @import("std");

pub const Color = enum(u8) {
    Black = 30,
    Red = 31,
    Green = 32,
    Yellow = 33,
    Blue = 34,
    Magenta = 35,
    Cyan = 36,
    White = 37,
    Default = 39,
};

pub const Style = struct {
    fg: ?Color = null,
    bg: ?Color = null,
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,

    pub fn toAnsi(self: Style, writer: *std.Io.Writer) !void {
        try writer.writeAll("\x1b[0");
        if (self.bold) try writer.writeAll(";1");
        if (self.italic) try writer.writeAll(";3");
        if (self.underline) try writer.writeAll(";4");

        if (self.fg) |c| try writer.print(";{d}", .{@intFromEnum(c)});
        if (self.bg) |c| try writer.print(";{d}", .{@intFromEnum(c) + 10});

        try writer.writeAll("m");
    }
};

pub const Span = struct {
    text: []const u8,
    style: Style = .{},

    pub fn init(text: []const u8, style: Style) Span {
        return .{
            .text = text,
            .style = style,
        };
    }
};

pub const Line = struct {
    spans: std.ArrayList(Span),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Line {
        return .{
            .spans = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Line) void {
        self.spans.deinit(self.allocator);
    }

    pub fn addSpan(self: *Line, span: Span) !void {
        try self.spans.append(self.allocator, span);
    }

    pub fn addText(self: *Line, text: []const u8) !void {
        try self.addSpan(Span.init(text, .{}));
    }

    pub fn render(self: *const Line, writer: *std.Io.Writer) !void {
        for (self.spans.items) |span| {
            try span.style.toAnsi(writer);
            try writer.writeAll(span.text);
        }
        try writer.writeAll("\x1b[0m");
    }
};
