const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const zunic = b.dependency("zunic", .{ .target = target, .optimize = optimize });

    // Keep one canonical corpus tree. The generated module copies the exact
    // shared corpora beside the Zig source so @embedFile can freeze
    // them into the benchmark executable.
    const generated = b.addWriteFiles();
    const root = generated.addCopyFile(b.path("zunic-width.zig"), "zunic-width.zig");
    _ = generated.addCopyDirectory(b.path("../texts"), "texts", .{});

    const module = b.createModule(.{
        .root_source_file = root,
        .target = target,
        .optimize = optimize,
    });
    module.addImport("zunic", zunic.module("zunic"));
    const executable = b.addExecutable(.{ .name = "zunic-width-bench", .root_module = module });
    b.installArtifact(executable);

    const tests_module = b.createModule(.{
        .root_source_file = root,
        .target = target,
        .optimize = optimize,
    });
    tests_module.addImport("zunic", zunic.module("zunic"));
    const tests = b.addTest(.{ .root_module = tests_module });
    b.step("test", "Test Zunic width over the shared corpora").dependOn(&b.addRunArtifact(tests).step);
}
