const std = @import("std");
pub const Pos = struct { x: usize, y: usize };

pub fn isDigitSlice(s: []const u8) bool {
    for (s) |c| {
        if (!std.ascii.isDigit(c))
            return false;
    }
    return s.len > 0;
}

pub fn parseKeySequence(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '<' and i + 4 < input.len and input[i + 1] == 'C' and input[i + 2] == '-') {
            const char = input[i + 3];
            if (input[i + 4] == '>') {
                if (char >= 'a' and char <= 'z') {
                    try out.append(allocator, char - 'a' + 1);
                } else if (char >= 'A' and char <= 'Z') {
                    try out.append(allocator, char - 'A' + 1);
                }
                i += 5;
                continue;
            }
        }
        try out.append(allocator, input[i]);
        i += 1;
    }

    return out.toOwnedSlice(allocator);
}

pub fn dumpToFile(io: std.Io, path: []const u8, content: []const u8) !void {
    const file = try std.Io.Dir.createFileAbsolute(io, path, .{});
    defer file.close(io);

    var write_buf: [4096]u8 = undefined;
    var writer = file.writer(io, &write_buf);

    try writer.interface.writeAll(content);
    try writer.interface.flush();
}
