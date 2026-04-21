const std = @import("std");
const utils = @import("../utils.zig");
const style = @import("../view/style.zig");
const ansi = @import("../view/ansi.zig");
const HistoryManager = @import("history.zig").HistoryManager;
const api = @import("../api/api.zig");

const TAB_SIZE: usize = 4;
pub const NS_TREESITTER: u32 = 1;
pub const NS_SEARCH: u32 = 2;
pub const NS_LSP: u32 = 3;

pub const ExMark = struct {
    logical_start: usize,
    logical_end: usize,
    style: style.Style,
    ns_id: u32,
    priority: u8,
};

/// Gap buffer implementation
pub const GapBuffer = struct {
    allocator: std.mem.Allocator,
    buffer: []u8,
    /// The physical index representing the start of the gap.
    /// This also corresponds to the logical position of the cursor.
    /// All characters from `buffer[0..gap_start]` are the text BEFORE the cursor
    gap_start: usize,
    /// The physical index representing the end of the gap.
    /// All characters from `buffer[gap_end..buffer.len]` are the text AFTER the cursor.
    gap_end: usize,
    /// associated filename
    filename: ?[]const u8,
    /// This field is used by R-engine to colorize text frames
    extmarks: std.ArrayList(ExMark),
    is_dirty: bool = true,
    ts_tree: ?*anyopaque = null,
    disable_history: bool = false,

    history: HistoryManager,

    const INITIAL_CAPACITY = 1024;

    /// Initializes an empty Gap Buffer with an initial capacity.
    /// The gap spans the entire buffer initially.
    pub fn init(allocator: std.mem.Allocator) !GapBuffer {
        const buf = try allocator.alloc(u8, INITIAL_CAPACITY);
        @memset(buf, 0);
        return GapBuffer{
            .allocator = allocator,
            .buffer = buf,
            .gap_start = 0,
            .gap_end = buf.len,
            .filename = null,
            .extmarks = .empty,
            .history = HistoryManager.init(allocator),
        };
    }

    pub fn find(self: *GapBuffer, query: []const u8) !void {
        self.extmarks.clearRetainingCapacity();
        if (query.len == 0) return;

        var i: usize = 0;
        const part1 = self.getFirst();
        while (std.mem.indexOfPos(u8, part1, i, query)) |pos| {
            try self.extmarks.append(self.allocator, .{ .ns_id = NS_SEARCH, .priority = 1, .logical_start = pos, .logical_end = pos + query.len, .style = .{ .bg = ansi.Magenta } });
            i = pos + query.len;
        }

        i = 0;
        const part2 = self.getSecond();
        while (std.mem.indexOfPos(u8, part2, i, query)) |pos| {
            const logical_pos = self.gap_start + pos;
            try self.extmarks.append(self.allocator, .{ .ns_id = NS_SEARCH, .priority = 1, .logical_start = logical_pos, .logical_end = logical_pos + query.len, .style = .{ .bg = ansi.Magenta } });
            i = pos + query.len;
        }
    }

    /// Initializes a Gap Buffer loaded with predefined text.
    /// The gap is placed exactly after the provided text, ready for appending.
    ///
    /// Note: This function creates its own internal copy of `filename`.
    /// The caller retains ownership of the passed `filename` argument and is
    /// responsible for freeing it if it was dynamically allocated.
    pub fn initFromFile(allocator: std.mem.Allocator, text: []const u8, filename: []const u8) !GapBuffer {
        const total_capacity = text.len + INITIAL_CAPACITY;
        const name = try allocator.dupe(u8, filename);
        errdefer allocator.free(name);
        const buf = try allocator.alloc(u8, total_capacity);

        @memcpy(buf[0..text.len], text);
        @memset(buf[text.len..total_capacity], 0);

        return GapBuffer{
            .allocator = allocator,
            .buffer = buf,
            .gap_start = text.len,
            .gap_end = total_capacity,
            .filename = name,
            .extmarks = .empty,
            .history = HistoryManager.init(allocator),
        };
    }

    /// Doubles the physical capacity of the buffer when the gap is exhausted.
    /// This requires allocating a new block, copying the left part, and moving the right part to the end.
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
        if (self.filename) |f| {
            self.allocator.free(f);
        }
        self.extmarks.deinit(self.allocator);
        self.history.deinit();
        self.allocator.free(self.buffer);
        if (self.ts_tree) |tree| api.c.ts_tree_delete(@as(?*api.c.TSTree, @ptrCast(@alignCast(tree))));
    }

    pub fn clearMarksByNamespace(self: *GapBuffer, ns_id: u32) void {
        var keep_idx: usize = 0;
        for (self.extmarks.items) |mark| {
            if (mark.ns_id != ns_id) {
                self.extmarks.items[keep_idx] = mark;
                keep_idx += 1;
            }
        }
        self.extmarks.shrinkRetainingCapacity(keep_idx);
    }

    /// Moves the cursor (and the gap) one character to the left.
    /// This physically takes the character just before the gap and copies it to the end of the gap.
    pub fn moveCursorLeft(self: *GapBuffer) void {
        if (self.gap_start > 0) {
            self.gap_start -= 1;
            self.gap_end -= 1;
            self.buffer[self.gap_end] = self.buffer[self.gap_start];
        }
    }

    /// Moves the cursor (and the gap) one character to the right.
    /// This physically takes the character just after the gap and copies it to the start of the gap.
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

    /// Inserts a character exactly at the cursor's logical position in O(1) time.
    /// Consumes one byte of the gap. Expands the buffer if the gap is empty.
    pub fn insertChar(self: *GapBuffer, char: u8) !void {
        if (self.gap_start == self.gap_end) {
            try self.expand();
        }

        self.buffer[self.gap_start] = char;
        self.gap_start += 1;
        self.is_dirty = true;
    }

    /// Removes the character immediately preceding the cursor in O(1) time.
    /// This simply expands the gap backwards by one byte.
    pub fn backspace(self: *GapBuffer) void {
        if (self.gap_start > 0) {
            self.gap_start -= 1;
        }
        self.is_dirty = true;
    }

    pub fn printDebug(self: *GapBuffer) void {
        std.debug.print("Texte: '{s}{s}' | start: {d}, end: {d}\n", .{
            self.buffer[0..self.gap_start],
            self.buffer[self.gap_end..self.buffer.len],
            self.gap_start,
            self.gap_end,
        });
    }

    /// Returns a slice pointing to the text physically located BEFORE the cursor.
    pub fn getFirst(self: *GapBuffer) []u8 {
        return self.buffer[0..self.gap_start];
    }

    /// Returns a slice pointing to the text physically located AFTER the cursor.
    pub fn getSecond(self: *GapBuffer) []u8 {
        return self.buffer[self.gap_end..self.buffer.len];
    }

    /// Calculates the 2D logical position (x, y) of the cursor by iterating
    /// through the left part of the buffer and counting newlines and tabs.
    pub fn getCursorPos(self: *GapBuffer) struct { x: usize, y: usize } {
        var x: usize = 1;
        var y: usize = 1;

        for (self.buffer[0..self.gap_start]) |c| {
            const is_continuation = ((c & 0xC0) == 0x80);
            if (c == '\n') {
                y += 1;
                x = 1;
            } else if (c == '\t') {
                x += TAB_SIZE;
            } else if (!is_continuation) {
                x += 1;
            }
        }

        return .{ .y = y, .x = x };
    }

    /// Moves the gap to an arbitrary (x, y) logical coordinate.
    /// This translates the logical 2D coordinate into a physical array index,
    /// and shifts the gap by copying blocks of memory.
    pub fn jumpTo(self: *GapBuffer, pos: utils.Pos) void {
        const gap_size = self.gap_end - self.gap_start;
        const logical_len = self.buffer.len - gap_size;

        var target_logical_idx: usize = 0;
        var current_y: usize = 1;
        var current_x: usize = 1;

        while (target_logical_idx < logical_len) {
            const physical_idx = if (target_logical_idx < self.gap_start)
                target_logical_idx
            else
                target_logical_idx + gap_size;

            const c = self.buffer[physical_idx];
            const is_continuation = ((c & 0xC0) == 0x80);

            if (!is_continuation) {
                if (current_y == pos.y and current_x >= pos.x) break;
            }
            if (current_y == pos.y and c == '\n') break;

            if (c == '\n') {
                current_y += 1;
                current_x = 1;
                if (current_y > pos.y) break;
            } else if (c == '\t') {
                current_x += TAB_SIZE;
            } else {
                current_x += 1;
            }

            target_logical_idx += 1;
        }

        if (target_logical_idx < self.gap_start) {
            const shift_len = self.gap_start - target_logical_idx;
            const dest = self.gap_end - shift_len;

            std.mem.copyBackwards(u8, self.buffer[dest .. dest + shift_len], self.buffer[target_logical_idx..self.gap_start]);
            self.gap_start -= shift_len;
            self.gap_end -= shift_len;
        } else if (target_logical_idx > self.gap_start) {
            const shift_len = target_logical_idx - self.gap_start;
            std.mem.copyForwards(u8, self.buffer[self.gap_start .. self.gap_start + shift_len], self.buffer[self.gap_end .. self.gap_end + shift_len]);
            self.gap_start += shift_len;
            self.gap_end += shift_len;
        }
    }

    pub fn jumpToLogical(self: *GapBuffer, target_logical: usize) void {
        const logical_len = self.buffer.len - (self.gap_end - self.gap_start);

        const safe_target = @min(target_logical, logical_len);

        if (safe_target == self.gap_start) return;

        if (safe_target < self.gap_start) {
            const shift = self.gap_start - safe_target;
            std.mem.copyBackwards(u8, self.buffer[self.gap_end - shift .. self.gap_end], self.buffer[safe_target..self.gap_start]);
            self.gap_start -= shift;
            self.gap_end -= shift;
        } else {
            const shift = safe_target - self.gap_start;
            std.mem.copyForwards(u8, self.buffer[self.gap_start .. self.gap_start + shift], self.buffer[self.gap_end .. self.gap_end + shift]);
            self.gap_start += shift;
            self.gap_end += shift;
        }
    }

    pub fn jumpToNextSearchResult(self: *GapBuffer) void {
        if (self.extmarks.items.len == 0) return;

        var target = self.extmarks.items[0].logical_start;
        for (self.extmarks.items) |mark| {
            if (mark.logical_start > self.gap_start) {
                if (mark.ns_id == NS_SEARCH) {
                    target = mark.logical_start;
                    break;
                }
            }
        }
        self.jumpToLogical(target);
    }

    pub fn jumpToPrevSearchResult(self: *GapBuffer) void {
        if (self.extmarks.items.len == 0) return;

        var target = self.extmarks.items[self.extmarks.items.len - 1].logical_start;

        var i: usize = self.extmarks.items.len;
        while (i > 0) {
            i -= 1;
            const mark = self.extmarks.items[i];
            if (mark.logical_start < self.gap_start) {
                if (mark.ns_id == NS_SEARCH) {
                    target = mark.logical_start;
                    break;
                }
            }
        }
        self.jumpToLogical(target);
    }

    /// Return real size (without gap)
    pub fn len(self: *const GapBuffer) usize {
        return self.buffer.len - (self.gap_end - self.gap_start);
    }

    /// Return the char at `logical_idx` O(1)
    pub fn charAt(self: *const GapBuffer, logical_idx: usize) ?u8 {
        if (logical_idx >= self.len()) return null;

        if (logical_idx < self.gap_start) {
            return self.buffer[logical_idx];
        } else {
            const gap_size = self.gap_end - self.gap_start;
            return self.buffer[logical_idx + gap_size];
        }
    }

    /// Allocate and return a slice of gap buffer text (the caller takes ownership)
    /// TODO: use @memcpy instead of byte per byte iteration
    /// see: https://github.com/pepedinho/dot/pull/26#discussion_r3051279747
    pub fn getLogicalRange(self: *const GapBuffer, allocator: std.mem.Allocator, start: usize, end: usize) ![]u8 {
        const safe_start = @min(start, self.len());
        const safe_end = @min(end, self.len());
        if (safe_start >= safe_end) return allocator.alloc(u8, 0);

        const result_len = safe_end - safe_start;
        var result = try allocator.alloc(u8, result_len);

        var i: usize = 0;
        while (i < result_len) : (i += 1) {
            result[i] = self.charAt(safe_start + i).?;
        }

        return result;
    }

    /// Find logical bounds of the line corresponding to `logical_idx`
    pub fn getLineBounds(self: *const GapBuffer, logical_idx: usize) struct { start: usize, end: usize } {
        const text_len = self.len();
        if (text_len == 0) return .{ .start = 0, .end = 0 };

        var start = @min(logical_idx, text_len - 1);
        while (start > 0 and self.charAt(start - 1).? != '\n') {
            start -= 1;
        }

        var end = @min(logical_idx, text_len);
        while (end < text_len and self.charAt(end).? != '\n') {
            end += 1;
        }

        if (end < text_len and self.charAt(end).? == '\n') {
            end += 1;
        }

        return .{ .start = start, .end = end };
    }

    pub fn getLogicalFromRowCol(self: *const GapBuffer, target_row: usize, target_col: usize) usize {
        var current_row: usize = 1;
        var current_col: usize = 1;
        const total_len = self.len();

        for (0..total_len) |i| {
            const c = self.charAt(i).?;
            const is_continuation = ((c & 0xC0) == 0x80);

            if (!is_continuation) {
                if (current_row == target_row and current_col >= target_col) return i;
            }

            if (c == '\n') {
                if (current_row == target_row) return i;

                current_row += 1;
                current_col = 1;
            } else if (c == '\t') {
                current_col += TAB_SIZE;
            } else if (!is_continuation) {
                current_col += 1;
            }
        }
        return total_len;
    }
};
