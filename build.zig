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

    const app = b.addModule("zigram_app", .{
        .root_source_file = b.path("src/app/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zigram", .module = core },
        },
    });

    const ui = b.addModule("zigram_ui", .{
        .root_source_file = b.path("src/ui/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zigram", .module = core },
            .{ .name = "zigram_app", .module = app },
        },
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

    const imgui = b.addLibrary(.{
        .linkage = .static,
        .name = "imgui",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libcpp = true,
        }),
    });
    const imgui_mod = imgui.root_module;
    imgui_mod.addIncludePath(b.path("vendor/imgui-1.93.0"));
    imgui_mod.addIncludePath(b.path("vendor/imgui-1.93.0/backends"));
    imgui_mod.addIncludePath(b.path("vendor/SDL3-3.4.20/include"));
    imgui_mod.addCSourceFiles(.{
        .root = b.path("vendor/imgui-1.93.0"),
        .files = &.{
            "imgui.cpp",
            "imgui_draw.cpp",
            "imgui_tables.cpp",
            "imgui_widgets.cpp",
            "backends/imgui_impl_sdl3.cpp",
            "backends/imgui_impl_sdlgpu3.cpp",
            // FreeType renders color emoji (CBDT bitmaps) which the stb
            // loader cannot; without it emoji fall back to monochrome.
            "misc/freetype/imgui_freetype.cpp",
        },
    });
    imgui_mod.addCMacro("IMGUI_ENABLE_FREETYPE", "1");
    // Headers and flags come from pkg-config (see README requirements).
    imgui_mod.linkSystemLibrary("freetype2", .{});
    // C ABI bridge between the Zig GUI and SDL3 + ImGui.
    imgui_mod.addCSourceFiles(.{
        .root = b.path("src/ui"),
        .files = &.{
            "gfx_shim.cpp",
            "gfx_widgets.cpp",
            "gfx_qr.cpp",
        },
    });

    const gui = b.addExecutable(.{
        .name = "zigram-gui",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/gui/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
            .imports = &.{
                .{ .name = "zigram", .module = core },
                .{ .name = "zigram_app", .module = app },
                .{ .name = "zigram_ui", .module = ui },
            },
        }),
    });
    // Prebuilt by cmake once (see README); SDL3's sources select platform
    // backends with generated config headers, which the build system cannot
    // reproduce reliably.
    gui.root_module.addObjectFile(b.path("vendor/sdl/libSDL3.a"));
    gui.root_module.linkLibrary(imgui);
    b.installArtifact(gui);

    const run_gui_step = b.step("run-gui", "Run zigram-gui");
    const run_gui = b.addRunArtifact(gui);
    run_gui.step.dependOn(b.getInstallStep());
    run_gui_step.dependOn(&run_gui.step);

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

    const app_tests = b.addTest(.{
        .root_module = app,
    });
    const run_app_tests = b.addRunArtifact(app_tests);

    // The QR encoder is pure Zig with no GUI or libc dependencies.
    const qr_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/ui/qr/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_qr_tests = b.addRunArtifact(qr_tests);

    // The theme is plain data: tokens, a built-in theme and a ZON loader.
    const theme_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/ui/theme/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_theme_tests = b.addRunArtifact(theme_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_core_tests.step);
    test_step.dependOn(&run_cli_tests.step);
    test_step.dependOn(&run_app_tests.step);
    test_step.dependOn(&run_qr_tests.step);
    test_step.dependOn(&run_theme_tests.step);

    const fmt_step = b.addFmt(.{
        .paths = b.pathList(&.{ "src", "build.zig" }),
    });
    b.step("fmt", "Format source files").dependOn(&fmt_step.step);
}
