const std = @import("std");

pub const Fs = struct {
    pub fn open(io: std.Io, path: []const u8) !std.Io.File {
        if (std.fs.path.isAbsolute(path)) {
            return std.Io.Dir.openFileAbsolute(io, path, .{ .mode = .read_only });
        } else return std.Io.Dir.cwd().openFile(io, path, .{ .mode = .read_only });
    }

    pub fn loadFast(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
        const file = try open(io, path);
        defer file.close(io);

        const file_size = try file.length(io);

        if (file_size == 0) {
            return allocator.alloc(u8, 0);
        }

        const mapped = try std.posix.mmap(null, file_size, std.posix.PROT{ .READ = true }, .{ .TYPE = .PRIVATE }, file.handle, 0);
        defer std.posix.munmap(mapped);

        return try allocator.dupe(u8, mapped[0..file_size]);
    }
};

// 
