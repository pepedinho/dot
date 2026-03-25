const std = @import("std");

pub const Fs = struct {
    pub fn open(path: []const u8) !std.fs.File {
        if (std.fs.path.isAbsolute(path)) {
            return std.fs.openFileAbsolute(path, .{ .mode = .read_only });
        } else return std.fs.cwd().openFile(path, .{ .mode = .read_only });
    }

    pub fn loadFast(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
        const file = try open(path);
        defer file.close();

        const file_size = try file.getEndPos();

        if (file_size == 0) {
            return allocator.alloc(u8, 0);
        }

        const mapped = try std.posix.mmap(null, file_size, std.posix.PROT.READ, .{ .TYPE = .PRIVATE }, file.handle, 0);
        defer std.posix.munmap(mapped);

        return try allocator.dupe(u8, mapped[0..file_size]);
    }
};

// 
