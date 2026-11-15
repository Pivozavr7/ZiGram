const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const core = b.addModule("zigram", .{
        .root_source_file = b.path("src/core/root.zig"),
        .target = target,
        .optimize = optimize,
        // TDLib is dynamically linked against libc and libm. Linking libc
        // makes std.DynLib use dlopen, which resolves those dependencies;
        // without it Zig's built-in ELF loader cannot run TDLib.
        .link_libc = true,
    });

    const cli = b.addExecutable(.{
        .name = "zigram-cli",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/cli.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigram", .module = core },
            },
        }),
    });
    b.installArtifact(cli);

    const run_step = b.step("run", "Run zigram-cli");
    const run_cli = b.addRunArtifact(cli);
    run_cli.step.dependOn(b.getInstallStep());
    run_cli.addPassthruArgs();
    run_step.dependOn(&run_cli.step);

    const run_cli_step = b.step("run-cli", "Run zigram-cli");
    run_cli_step.dependOn(&run_cli.step);

    const core_tests = b.addTest(.{
        .root_module = core,
    });
    const run_core_tests = b.addRunArtifact(core_tests);

    const cli_tests = b.addTest(.{
        .root_module = cli.root_module,
    });
    const run_cli_tests = b.addRunArtifact(cli_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_core_tests.step);
    test_step.dependOn(&run_cli_tests.step);

    const fmt_step = b.addFmt(.{
        .paths = b.pathList(&.{ "src", "build.zig" }),
    });
    b.step("fmt", "Format source files").dependOn(&fmt_step.step);
}
