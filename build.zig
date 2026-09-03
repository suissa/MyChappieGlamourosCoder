const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Module exposing the MyChappie Glamouros Coder library for semantic plane integration
    const mod = b.addModule("mychappie_coder", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Autonomous coding assistant executable
    const exe = b.addExecutable(.{
        .name = "mychappie-coder",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "mychappie_coder", .module = mod },
            },
        }),
    });

    b.installArtifact(exe);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run MyChappie Glamouros Coder CLI");
    run_step.dependOn(&run_cmd.step);

    // Deterministic/default tests. The autonomous agent loop is intentionally
    // excluded and lives under the explicit test-integration step below.
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run MyChappie unit and component tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // Explicit integration test: exercises the autonomous loop and a real
    // filesystem write, then cleans the generated artifact.
    const integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/agent_integration.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "mychappie_coder", .module = mod },
            },
        }),
    });
    const run_integration_tests = b.addRunArtifact(integration_tests);

    const integration_step = b.step("test-integration", "Run autonomous agent integration tests");
    integration_step.dependOn(&run_integration_tests.step);
}
