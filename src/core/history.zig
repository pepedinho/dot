const std = @import("std");
const gap = @import("gap.zig");

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

pub const HistoryManager = struct {
    allocator: std.mem.Allocator,
    undo_stack: std.ArrayList(Transaction),
    current_transaction: ?Transaction,
    last_edit_time: i64,

    pub fn init(allocator: std.mem.Allocator) HistoryManager {
        return .{
            .allocator = allocator,
            .undo_stack = .empty,
            .current_transaction = null,
            .last_edit_time = 0,
        };
    }

    pub fn deinit(self: *HistoryManager) void {
        if (self.current_transaction) |*t| t.deinit(self.allocator);
        for (self.undo_stack.items) |*t| t.deinit(self.allocator);
        self.undo_stack.deinit(self.allocator);
    }

    pub fn commit(self: *HistoryManager) !void {
        if (self.current_transaction) |*t| {
            if (t.edits.items.len > 0) {
                try self.undo_stack.append(self.allocator, t.*);
            } else {
                t.deinit(self.allocator);
            }
            self.current_transaction = null;
        }
    }

    pub fn recordInsert(self: *HistoryManager, pos: usize, char: u8) !void {
        const now = std.time.milliTimestamp();

        if (self.current_transaction == null or (now - self.last_edit_time > 1000)) {
            try self.commit();
            self.current_transaction = Transaction{ .edits = .empty };
        }

        try self.current_transaction.?.edits.append(self.allocator, .{ .kind = .insert, .pos = pos, .char = char });
        self.last_edit_time = now;

        if (char == ' ' or char == '\n' or char == '.' or char == '(' or char == ')') {
            try self.commit();
        }
    }

    pub fn recordDelete(self: *HistoryManager, pos: usize, char: u8) !void {
        const now = std.time.milliTimestamp();

        if (self.current_transaction == null or (now - self.last_edit_time > 1000)) {
            try self.commit();
            self.current_transaction = Transaction{ .edits = .empty };
        }

        try self.current_transaction.?.edits.append(self.allocator, .{ .kind = .delete, .pos = pos, .char = char });
        self.last_edit_time = now;
    }

    pub fn undo(self: *HistoryManager, buf: *gap.GapBuffer) !void {
        try self.commit();

        if (self.undo_stack.pop()) |*t| {
            var i: usize = t.edits.items.len;
            while (i > 0) {
                i -= 1;
                const edit = t.edits.items[i];

                // buf.jumpToLogical(edit.pos);

                switch (edit.kind) {
                    .insert => {
                        buf.jumpToLogical(edit.pos + 1);
                        buf.backspace();
                    },
                    .delete => {
                        buf.jumpToLogical(edit.pos);
                        try buf.insertChar(edit.char);
                    },
                }
            }
            var mut_t = t.*;
            mut_t.deinit(self.allocator);
        }
    }
};
