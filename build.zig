const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "dot",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.addIncludePath(b.path("vendor/lua/src/"));
    exe.linkLibC();

    const lua_sources = &[_][]const u8{
        "lapi.c",   "lcode.c",    "lctype.c",  "ldebug.c",   "ldo.c",     "ldump.c",    "lfunc.c",    "lgc.c",
        "llex.c",   "lmem.c",     "lobject.c", "lopcodes.c", "lparser.c", "lstate.c",   "lstring.c",  "ltable.c",
        "ltm.c",    "lundump.c",  "lvm.c",     "lzio.c",     "lauxlib.c", "lbaselib.c", "lcorolib.c", "ldblib.c",
        "liolib.c", "lmathlib.c", "loadlib.c", "loslib.c",   "lstrlib.c", "ltablib.c",  "lutf8lib.c", "linit.c",
    };

    for (lua_sources) |file| {
        exe.addCSourceFile(.{
            .file = b.path(b.fmt("vendor/lua/src/{s}", .{file})),
            .flags = &[_][]const u8{ "-std=c99", "-O2" },
        });
    }

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
