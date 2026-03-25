const std = @import("std");

const TAB_SIZE: usize = 8;

pub const GapBuffer = struct {
    allocator: std.mem.Allocator,
    buffer: []u8,
    gap_start: usize,
    gap_end: usize,

    const INITIAL_CAPACITY = 1024;

    pub fn init(allocator: std.mem.Allocator) !GapBuffer {
        const buf = try allocator.alloc(u8, INITIAL_CAPACITY);
        @memset(buf, 0);
        return GapBuffer{
            .allocator = allocator,
            .buffer = buf,
            .gap_start = 0,
            .gap_end = buf.len,
        };
    }

    pub fn initFromFile(allocator: std.mem.Allocator, text: []const u8) !GapBuffer {
        const total_capacity = text.len + INITIAL_CAPACITY;
        const buf = try allocator.alloc(u8, total_capacity);

        @memcpy(buf[0..text.len], text);
        @memset(buf[text.len..total_capacity], 0);

        return GapBuffer{
            .allocator = allocator,
            .buffer = buf,
            .gap_start = text.len,
            .gap_end = total_capacity,
        };
    }

    fn expand(self: *GapBuffer) !void {
        const new_capacity = self.buffer.len * 2;
        const buf = try self.allocator.alloc(u8, new_capacity);
        @memmove(buf[0..self.gap_start], self.buffer[0..self.gap_start]);

        const right_part_len = self.buffer.len - self.gap_end;
        const new_gap_end = new_capacity - right_part_len;

        @memcpy(buf[new_gap_end..new_capacity], self.buffer[self.gap_end..self.buffer.len]);

        self.allocator.free(self.buffer);
        self.buffer = buf;
        self.gap_end = new_gap_end;
    }

    pub fn deinit(self: *GapBuffer) void {
        self.allocator.free(self.buffer);
    }

    pub fn moveCursorLeft(self: *GapBuffer) void {
        if (self.gap_start > 0) {
            self.gap_start -= 1;
            self.gap_end -= 1;
            self.buffer[self.gap_end] = self.buffer[self.gap_start];
        }
    }

    pub fn moveCursorRight(self: *GapBuffer) void {
        if (self.gap_end < self.buffer.len) {
            self.buffer[self.gap_start] = self.buffer[self.gap_end];
            self.gap_start += 1;
            self.gap_end += 1;
        }
    }

    pub fn moveCursorUp(self: *GapBuffer) void {
        const pos = self.getCursorPos();
        if (pos.y == 1) return;

        while (self.gap_start > 0 and self.buffer[self.gap_start - 1] != '\n') {
            self.moveCursorLeft();
        }

        self.moveCursorLeft();

        while (self.gap_start > 0 and self.buffer[self.gap_start - 1] != '\n') {
            self.moveCursorLeft();
        }

        var target_x = pos.x;
        while (target_x > 1 and self.gap_end < self.buffer.len and self.buffer[self.gap_end] != '\n') {
            self.moveCursorRight();
            target_x -= 1;
        }
    }

    pub fn moveCursorDown(self: *GapBuffer) void {
        const pos = self.getCursorPos();

        while (self.gap_end < self.buffer.len and self.buffer[self.gap_end] != '\n') {
            self.moveCursorRight();
        }

        if (self.gap_end == self.buffer.len) return;

        self.moveCursorRight();
        var target_x = pos.x;
        while (target_x > 1 and self.gap_end < self.buffer.len and self.buffer[self.gap_end] != '\n') {
            self.moveCursorRight();
            target_x -= 1;
        }
    }

    pub fn insertChar(self: *GapBuffer, char: u8) !void {
        if (self.gap_start == self.gap_end) {
            try self.expand();
        }

        self.buffer[self.gap_start] = char;
        self.gap_start += 1;
    }

    pub fn backspace(self: *GapBuffer) void {
        if (self.gap_start > 0) {
            self.gap_start -= 1;
        }
    }

    pub fn printDebug(self: *GapBuffer) void {
        std.debug.print("Texte: '{s}{s}' | start: {d}, end: {d}\n", .{
            self.buffer[0..self.gap_start],
            self.buffer[self.gap_end..self.buffer.len],
            self.gap_start,
            self.gap_end,
        });
    }

    pub fn getFirst(self: *GapBuffer) []u8 {
        return self.buffer[0..self.gap_start];
    }

    pub fn getSecond(self: *GapBuffer) []u8 {
        return self.buffer[self.gap_end..self.buffer.len];
    }

    pub fn getCursorPos(self: *GapBuffer) struct { x: usize, y: usize } {
        var x: usize = 1;
        var y: usize = 1;

        for (self.buffer[0..self.gap_start]) |c| {
            if (c == '\n') {
                y += 1;
                x = 1;
            } else if (c == '\t') {
                x += TAB_SIZE;
            } else {
                x += 1;
            }
        }

        return .{ .y = y, .x = x };
    }
};
