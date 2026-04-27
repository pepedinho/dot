const std = @import("std");
const actions = @import("action.zig");

const Action = actions.Action;
const ActionQueue = actions.ActionQueue;

/// Represent a recurring task managed by the `Scheduler`.
pub const Job = struct {
    /// The payload to be pushed to the Editor's action queue.
    action: Action,
    /// The target duration between each execution in millisecond.
    interval_ms: i64,
    /// The timestamp of the last scheduled execution.
    last_run: i64,
};

/// A fixed-size, allocation-free task scheduler.
/// It polls registered Jobs and pushes their actions to the main queue
/// when their time interval_ms elapsed.
pub const Scheduler = struct {
    /// Fixed pool of 32 possible recurring jobs. Null means the slot is free.
    jobs: [32]?Job = .{null} ** 32,
    io: std.Io,

    /// Registers a new recursing action in the first available slot.
    /// The job will trigger its first execution after `interval_ms` has passed.
    pub fn add(self: *Scheduler, action: Action, interval_ms: i64) !void {
        const now = std.Io.Clock.now(.real, self.io).toMilliseconds();
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

    /// Evakuate all active jobs against the current timestamp and pushes
    /// ready actions to the provided queue.
    pub fn update(self: *Scheduler, queue: *ActionQueue) !void {
        const now = std.Io.Clock.now(.real, self.io).toMilliseconds();
        for (&self.jobs) |*slot| {
            if (slot.*) |*job| {
                var catch_up_limit: usize = 0;

                // Catch-up mechanism: If the main thread lagged (e.g. heavy IO),
                // we trigger the missed actions to maintain a steady rate.
                // We cap this at 10 to avoid saturating the ActionQueue during a lag spike.
                while (now - job.last_run >= job.interval_ms and catch_up_limit < 10) {
                    try queue.push(job.action);
                    job.last_run += job.interval_ms;
                    catch_up_limit += 1;
                }

                // Flood prevention: If the OS went to sleep or the app froze for a long time,
                // the job is heavily desynced. We reset the timer to prevent the queue
                // from being bombarded with backlogged actions in the next frames.
                if (now - job.last_run > job.interval_ms * 10) {
                    job.last_run = now;
                }
            }
        }
    }
};
