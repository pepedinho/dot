const std = @import("std");
const ansi = @import("ansi.zig");

// pub const Color = enum(u8) {
//     Black = 30,
//     Red = 31,
//     Green = 32,
//     Yellow = 33,
//     Blue = 34,
//     Magenta = 35,
//     Cyan = 36,
//     White = 37,
//     Default = 39,
// };

pub const Color = union(enum) {
    Default,
    Index: u8,
    Rgb: struct { r: u8, g: u8, b: u8 },

    pub fn writeFg(self: Color, writer: *std.Io.Writer) !void {
        switch (self) {
            .Default => try writer.writeAll("\x1b[39m"),
            .Index => |i| try writer.print("\x1b[38;5;{d}m", .{i}),
            .Rgb => |rgb| try writer.print("\x1b[38;2;{d};{d};{d}m", .{ rgb.r, rgb.g, rgb.b }),
        }
    }

    pub fn writeBg(self: Color, writer: anytype) !void {
        switch (self) {
            .Default => try writer.writeAll("\x1b[49m"),
            .Index => |i| try writer.print("\x1b[48;5;{d}m", .{i}),
            .Rgb => |rgb| try writer.print("\x1b[48;2;{d};{d};{d}m", .{ rgb.r, rgb.g, rgb.b }),
        }
    }
};

pub const Effect = union(enum) {
    None,
    Shimmer: ansi.ShimmerOptions,
};

pub const Style = struct {
    fg: Color = .Default,
    bg: Color = .Default,
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,
    effect: Effect = .None,

    pub fn toAnsi(self: Style, writer: *std.Io.Writer) !void {
        try writer.writeAll("\x1b[0m");

        try self.fg.writeFg(writer);
        try self.bg.writeBg(writer);

        if (self.bold) try writer.writeAll("\x1b[1m");
        if (self.italic) try writer.writeAll("\x1b[3m");
        if (self.underline) try writer.writeAll("\x1b[4m");
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

    pub fn render(self: Span, writer: anytype, phase: f32) !void {
        try self.style.toAnsi(writer);

        switch (self.style.effect) {
            .None => {
                try writer.writeAll(self.text);
            },
            .Shimmer => |opts| {
                try ansi.writeShimmerText(writer, self.text, phase, opts);
            },
        }
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

    pub fn render(self: *const Line, writer: *std.Io.Writer, phase: f32) !void {
        for (self.spans.items) |span| {
            try span.render(writer, phase);
        }
        try writer.writeAll("\x1b[0m");
    }
};
