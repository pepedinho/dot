const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zui_mod = b.addModule("zui", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const mod_tests = b.addTest(.{
        .root_module = zui_mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_mod_tests.step);

    const demo_exe = b.addExecutable(.{
        .name = "demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/demo.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    demo_exe.root_module.addImport("zui", zui_mod);

    const install_demo = b.addInstallArtifact(demo_exe, .{});

    const run_demo_cmd = b.addRunArtifact(demo_exe);
    run_demo_cmd.step.dependOn(&install_demo.step);

    if (b.args) |args| {
        run_demo_cmd.addArgs(args);
    }

    const run_demo_step = b.step("run-demo", "Run the demo example");
    run_demo_step.dependOn(&run_demo_cmd.step);
}

