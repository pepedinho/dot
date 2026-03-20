const std = @import("std");

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
            } else {
                x += 1;
            }
        }

        return .{ .y = y, .x = x };
    }
};
