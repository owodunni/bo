const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "bo",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.addIncludePath(.{ .path = "c" });
    exe.addCSourceFile(.{
        .file = .{ .path = "c/sqlite3.c" },
        .flags = &[_][]const u8{"-std=c99"},
    });
    exe.linkLibC();
    exe.installHeader("c/sqlite3.h", "sqlite3.h");

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const lib_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/sqlite.zig" },
        .target = target,
        .optimize = optimize,
    });

    lib_unit_tests.addIncludePath(.{ .path = "c" });
    lib_unit_tests.addCSourceFile(.{
        .file = .{ .path = "c/sqlite3.c" },
        .flags = &[_][]const u8{"-std=c99"},
    });
    lib_unit_tests.linkLibC();
    lib_unit_tests.installHeader("c/sqlite3.h", "sqlite3.h");

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}

fn tmp(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const sqlite_lib = b.addStaticLibrary(.{
        .name = "sqlite",
        .target = target,
        .optimize = optimize,
    });

    sqlite_lib.addIncludePath(.{ .path = "c/" });
    sqlite_lib.addCSourceFile(.{
        .file = .{ .path = "c/sqlite3.c" },
        .flags = &[_][]const u8{"-std=c99"},
    });
    sqlite_lib.linkLibC();
    sqlite_lib.installHeader("c/sqlite3.h", "sqlite3.h");

    b.installArtifact(sqlite_lib);

    //const sqlite_unit_tests = b.addTest(.{
    //    .root_source_file = .{ .path = "src/sqlite.zig" },
    //    .target = target,
    //    .optimize = optimize,
    //});

    //sqlite_unit_tests.linkLibrary(lib);

    //const run_sqlite_unit_tests = b.addRunArtifact(sqlite_unit_tests);
}
