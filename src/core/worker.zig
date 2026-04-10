const std = @import("std");

pub const JobResult = struct {
    /// Lua function ID
    ref_id: c_int,
    /// Command output text
    output: ?[]const u8,
    /// Command status
    success: bool,
};

pub const JobManager = struct {
    allocator: std.mem.Allocator,
    mutex: std.Thread.Mutex,
    completed_jobs: std.ArrayList(JobResult),

    pub fn init(allocator: std.mem.Allocator) JobManager {
        return .{
            .allocator = allocator,
            .mutex = .{},
            .completed_jobs = .empty,
        };
    }

    pub fn deinit(self: *JobManager) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        for (self.completed_jobs.items) |j| {
            if (j.output) |out| {
                self.allocator.free(out);
            }
        }
        self.completed_jobs.deinit(self.allocator);
    }

    pub fn pushResult(self: *JobManager, result: JobResult) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.completed_jobs.append(self.allocator, result) catch {};
    }

    pub fn popResult(self: *JobManager) ?JobResult {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.completed_jobs.items.len == 0) return null;
        return self.completed_jobs.orderedRemove(0);
    }
};

pub fn worker(job_mgr: *JobManager, allocator: std.mem.Allocator, cmd: []const u8, ref_id: c_int) void {
    defer allocator.free(cmd);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    var args: std.ArrayList([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, cmd, ' ');
    while (it.next()) |arg| {
        if (arg.len > 0) args.append(arena_alloc, arg) catch {};
    }

    if (args.items.len == 0) {
        job_mgr.pushResult(.{ .ref_id = ref_id, .output = null, .success = false });
        return;
    }

    const result = std.process.Child.run(.{
        .allocator = arena_alloc,
        .argv = args.items,
        .max_output_bytes = 10 * 1024 * 1024,
    }) catch {
        job_mgr.pushResult(.{ .ref_id = ref_id, .output = null, .success = false });
        return;
    };

    const output_copy = allocator.dupe(u8, result.stdout) catch null;
    const success = result.term == .Exited and result.term.Exited == 0;

    job_mgr.pushResult(.{
        .ref_id = ref_id,
        .output = output_copy,
        .success = success,
    });
}
