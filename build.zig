const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Fetch libxev dependency
    const xev_dep = b.dependency("libxev", .{ .target = target, .optimize = optimize });
    const xev_module = xev_dep.module("xev");

    // Create the screenlogic library module (the core library for FFI/Swift interop)
    const screenlogic_mod = b.addModule("screenlogic", .{
        .root_source_file = b.path("src/screenlogic.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "xev", .module = xev_module },
        },
    });

    // Create the CLI executable
    const exe = b.addExecutable(.{
        .name = "aquazig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "screenlogic", .module = screenlogic_mod },
                .{ .name = "xev", .module = xev_module },
            },
        }),
    });

    b.installArtifact(exe);

    // Run step
    const run_step = b.step("run", "Run the CLI application");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Create test module
    const test_mod = b.addModule("screenlogic_test", .{
        .root_source_file = b.path("src/screenlogic.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "xev", .module = xev_module },
        },
    });

    // Library tests
    const lib_tests = b.addTest(.{
        .root_module = test_mod,
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);

    // Test step
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_tests.step);

    // Check step for IDE integration
    const check_mod = b.addModule("screenlogic_check", .{
        .root_source_file = b.path("src/screenlogic.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "xev", .module = xev_module },
        },
    });

    const check = b.addTest(.{
        .root_module = check_mod,
    });
    const check_step = b.step("check", "Check if code compiles");
    check_step.dependOn(&check.step);
}
