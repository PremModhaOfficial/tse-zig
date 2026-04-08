const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Main executable
    const exe = b.addExecutable(.{
        .name = "spatial-engine",
        .root_module = root_module,
    });

    // Link Notcurses based on platform
    linkNotcurses(exe, target);

    // Disable UBSAN for release builds (Notcurses has known UB)
    if (optimize != .Debug) {
        exe.root_module.sanitize_c = false;
    }

    b.installArtifact(exe);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the spatial engine");
    run_step.dependOn(&run_cmd.step);

    // Unit tests
    const unit_tests = b.addTest(.{
        .root_module = root_module,
    });
    linkNotcurses(unit_tests, target);

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Check step (compile without linking for faster feedback)
    const check = b.addExecutable(.{
        .name = "spatial-engine",
        .root_module = root_module,
    });
    linkNotcurses(check, target);
    const check_step = b.step("check", "Check if the code compiles");
    check_step.dependOn(&check.step);
}

fn linkNotcurses(compile: *std.Build.Step.Compile, target: std.Build.ResolvedTarget) void {
    // Link libc (required for Notcurses)
    compile.linkLibC();

    const os_tag = target.result.os.tag;

    if (os_tag == .linux) {
        // Linux: use pkg-config
        compile.linkSystemLibrary("notcurses");
    } else if (os_tag == .macos) {
        // macOS: Homebrew paths
        compile.addIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
        compile.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
        compile.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
        compile.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });
        compile.linkSystemLibrary("notcurses");
    } else {
        @panic("Unsupported platform. Windows support planned for Phase 3.");
    }
}
