const core = @import("core.zig");
const buffer = @import("gap.zig");

/// Action who can be done by editor executor
/// you can combinate Action to create other action,
/// they will be executed sequencialy in the editor loop
pub const Action = union(enum) {
    InsertChar: u8,
    InsertNewLine,
    DeleteChar,
    MoveLeft,
    MoveRight,
    MoveUp,
    MoveDown,
    SetMode: core.Mode,
    Append,
    AppendNewLine,
    CreatePop: core.PopBuilder,
    CommandChar: u8,
    CommandBackspace,
    ExecuteCommand,
    ClearCommandBuf,
    UpdateDebugBuffer: *buffer.GapBuffer,
    NextSearchResult,
    PrevSearchResult,
    YankLine,
    Past,
    Undo,
    // SplitView,
    // GotoView: u8,
    Quit,
    Tick,
};

/// ActionQueue is the Action constainer that the `Scheduler` use to store Action in a ring stack-allocatd buffer
pub const ActionQueue = struct {
    buffer: [256]Action = undefined,
    head: usize = 0,
    tail: usize = 0,

    pub fn push(self: *ActionQueue, action: Action) core.CoreError!void {
        const next_head = (self.head + 1) % self.buffer.len;
        if (next_head == self.tail)
            return core.CoreError.QueueFull;
        self.buffer[self.head] = action;
        self.head = next_head;
    }

    pub fn pop(self: *ActionQueue) ?Action {
        if (self.head == self.tail) return null; // empty queue

        const action = self.buffer[self.tail];
        self.tail = (self.tail + 1) % self.buffer.len;
        return action;
    }

    pub fn count(self: *ActionQueue) usize {
        if (self.head >= self.tail) {
            return self.head - self.tail;
        } else return self.buffer.len - self.tail + self.head;
    }
};
