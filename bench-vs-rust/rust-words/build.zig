const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const zunic = b.dependency("zunic", .{ .target = target, .optimize = optimize });

    // Same arrangement as ../rust-wrap: one canonical corpus tree, copied
    // beside the Zig source so @embedFile can freeze the exact same bytes the
    // Rust peer reads from disk.
    const generated = b.addWriteFiles();
    const root = generated.addCopyFile(b.path("zunic-words.zig"), "zunic-words.zig");
    _ = generated.addCopyDirectory(b.path("../texts"), "texts", .{});

    const module = b.createModule(.{
        .root_source_file = root,
        .target = target,
        .optimize = optimize,
    });
    module.addImport("zunic", zunic.module("zunic"));
    const executable = b.addExecutable(.{ .name = "zunic-words-bench", .root_module = module });
    b.installArtifact(executable);

    const tests_module = b.createModule(.{
        .root_source_file = root,
        .target = target,
        .optimize = optimize,
    });
    tests_module.addImport("zunic", zunic.module("zunic"));
    const tests = b.addTest(.{ .root_module = tests_module });
    b.step("test", "Test Zunic word bounds over the shared corpora").dependOn(&b.addRunArtifact(tests).step);
}
