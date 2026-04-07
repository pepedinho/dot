const std = @import("std");

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
};

pub const ShimmerOptions = struct {
    base_color: Color,
    highlight_color: Color,
    wave_width: f32 = 8.0,
};

pub const hide_cursor = "\x1b[?25l";
pub const show_cursor = "\x1b[?25h";
pub const clear_screen = "\x1b[2J\x1b[H";

pub fn goto(writer: *std.Io.Writer, row: usize, col: usize) !void {
    try writer.print("\x1b[{d};{d}H", .{ row, col });
}

fn lerpColor(c1: Color, c2: Color, t: f32) Color {
    const clamped_t = if (t < 0.0) 0.0 else if (t > 1.0) 1.0 else t;

    return Color{
        .r = @intFromFloat(@round(@as(f32, @floatFromInt(c1.r)) + (@as(f32, @floatFromInt(c2.r)) - @as(f32, @floatFromInt(c1.r))) * clamped_t)),
        .g = @intFromFloat(@round(@as(f32, @floatFromInt(c1.g)) + (@as(f32, @floatFromInt(c2.g)) - @as(f32, @floatFromInt(c1.g))) * clamped_t)),
        .b = @intFromFloat(@round(@as(f32, @floatFromInt(c1.b)) + (@as(f32, @floatFromInt(c2.b)) - @as(f32, @floatFromInt(c1.b))) * clamped_t)),
    };
}

pub fn writeShimmerText(
    writer: *std.Io.Writer,
    text: []const u8,
    phase: f32,
    options: ShimmerOptions,
) !void {
    const cycle_lenght = @as(f32, @floatFromInt(text.len)) + (options.wave_width * 2.0);
    var local_phase = phase;
    while (local_phase > cycle_lenght) {
        local_phase -= cycle_lenght;
    }

    for (text, 0..) |char, i| {
        const pos: f32 = @floatFromInt(i);
        const adjusted_phase = local_phase - options.wave_width;
        const dist = @abs(pos - adjusted_phase);

        var intensity: f32 = 0.0;

        if (dist < options.wave_width) {
            intensity = 1.0 - (dist / options.wave_width);
        }

        const current_color = lerpColor(options.base_color, options.highlight_color, intensity);
        try writer.print("\x1b[38;2;{d};{d};{d}m{c}", .{
            current_color.r,
            current_color.g,
            current_color.b,
            char,
        });
        try writer.writeAll("\x1b[0m");
    }
}
