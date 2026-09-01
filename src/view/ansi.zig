const std = @import("std");
const zui = @import("zui");

pub const Rgb = struct { r: u8, g: u8, b: u8 };

pub const ShimmerOptions = struct {
    base_color: Rgb,
    highlight_color: Rgb,
    wave_width: f32 = 8.0,
};

fn lerpColor(c1: Rgb, c2: Rgb, t: f32) Rgb {
    const clamped_t = if (t < 0.0) 0.0 else if (t > 1.0) 1.0 else t;
    return .{
        .r = @intFromFloat(@round(@as(f32, @floatFromInt(c1.r)) + (@as(f32, @floatFromInt(c2.r)) - @as(f32, @floatFromInt(c1.r))) * clamped_t)),
        .g = @intFromFloat(@round(@as(f32, @floatFromInt(c1.g)) + (@as(f32, @floatFromInt(c2.g)) - @as(f32, @floatFromInt(c1.g))) * clamped_t)),
        .b = @intFromFloat(@round(@as(f32, @floatFromInt(c1.b)) + (@as(f32, @floatFromInt(c2.b)) - @as(f32, @floatFromInt(c1.b))) * clamped_t)),
    };
}

pub fn applyShimmerToBuffer(
    buf: *zui.Buffer,
    x: u16,
    y: u16,
    text: []const u8,
    phase: f32,
    options: ShimmerOptions,
) void {
    const cycle_length = @as(f32, @floatFromInt(text.len)) + (options.wave_width * 2.0);
    var local_phase = phase;
    while (local_phase > cycle_length) {
        local_phase -= cycle_length;
    }

    var current_x = x;
    var view = std.unicode.Utf8View.init(text) catch return;
    var iter = view.iterator();

    while (iter.nextCodepointSlice()) |codepoint_slice| {
        if (current_x >= buf.width) break;

        const pos: f32 = @floatFromInt(current_x - x);
        const adjusted_phase = local_phase - options.wave_width;
        const dist = @abs(pos - adjusted_phase);

        var intensity: f32 = 0.0;
        if (dist < options.wave_width) {
            intensity = 1.0 - (dist / options.wave_width);
        }

        const current_color = lerpColor(options.base_color, options.highlight_color, intensity);
        const style = zui.Style{ .fg = .{ .RGB = .{ .r = current_color.r, .g = current_color.g, .b = current_color.b } } };

        if (buf.get(current_x, y)) |cell| {
            cell.setSymbol(codepoint_slice);
            cell.setStyle(style);
        }
        current_x += 1;
    }
}

pub fn writeShimmerText(
    writer: anytype,
    text: []const u8,
    phase: f32,
    options: ShimmerOptions,
) !void {
    const cycle_length = @as(f32, @floatFromInt(text.len)) + (options.wave_width * 2.0);
    var local_phase = phase;
    while (local_phase > cycle_length) {
        local_phase -= cycle_length;
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
        try writer.writeAll("\x1b[39m");
    }
}
