const std = @import("std");

pub const EditKind = enum { insert, delete };

pub const Edit = struct {
    kind: EditKind,
    pos: usize,
    char: u8,
};

pub const Transaction = struct {
    edits: std.ArrayList(Edit),

    pub fn deinit(self: *Transaction, allocator: std.mem.Allocator) void {
        self.edits.deinit(allocator);
    }
};
