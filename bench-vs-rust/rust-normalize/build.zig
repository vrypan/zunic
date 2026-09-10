const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const zunic = b.dependency("zunic", .{ .target = target, .optimize = optimize });
    const generated = b.addWriteFiles();
    const root = generated.addCopyFile(b.path("zunic-normalize.zig"), "zunic-normalize.zig");
    _ = generated.addCopyDirectory(b.path("../texts"), "texts", .{});
    const module = b.createModule(.{ .root_source_file = root, .target = target, .optimize = optimize });
    module.addImport("zunic", zunic.module("zunic"));
    const executable = b.addExecutable(.{ .name = "zunic-normalize", .root_module = module });
    b.installArtifact(executable);
    const tests_module = b.createModule(.{ .root_source_file = root, .target = target, .optimize = optimize });
    tests_module.addImport("zunic", zunic.module("zunic"));
    b.step("test", "Test Zunic canonical normalization over shared corpora")
        .dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = tests_module })).step);
}
