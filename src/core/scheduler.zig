const std = @import("std");
const actions = @import("action.zig");

const Action = actions.Action;
const ActionQueue = actions.ActionQueue;

pub const Job = struct {
    action: Action,
    interval_ms: i64,
    last_run: i64,
};

pub const Scheduler = struct {
    jobs: [32]?Job = .{null} ** 32,

    pub fn add(self: *Scheduler, action: Action, interval_ms: i64) !void {
        const now = std.time.milliTimestamp();
        for (&self.jobs) |*slot| {
            if (slot.* == null) {
                slot.* = .{
                    .action = action,
                    .interval_ms = interval_ms,
                    .last_run = now,
                };
                return;
            }
        }
        return error.SchedulerFull;
    }

    pub fn update(self: *Scheduler, queue: *ActionQueue) !void {
        const now = std.time.milliTimestamp();
        for (&self.jobs) |*slot| {
            if (slot.*) |*job| {
                var catch_up_limit: usize = 0;
                while (now - job.last_run >= job.interval_ms and catch_up_limit < 10) {
                    try queue.push(job.action);
                    job.last_run += job.interval_ms;
                    catch_up_limit += 1;
                }

                if (now - job.last_run > job.interval_ms * 10) {
                    job.last_run = now;
                }
            }
        }
    }
};
