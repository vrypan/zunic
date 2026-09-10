const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const zunic = b.dependency("zunic", .{ .target = target, .optimize = optimize });
    // Copy the current sources into a generated module so private diagnostics
    // can access internal engines without changing the package's public API.
    const diagnostic_sources = b.addWriteFiles();
    _ = diagnostic_sources.addCopyDirectory(b.path("../../src"), "src", .{});
    // The engines moved into enforced modules, so the bridge goes through the
    // same graph the library uses rather than importing files by name. Its own
    // module holds only the bridge file: pulling an engine's source in here as
    // well would put one file in two modules, which Zig rejects.
    const src = diagnostic_sources.getDirectory();
    const module = struct {
        fn make(owner: *std.Build, dir: std.Build.LazyPath, path: []const u8, t2: std.Build.ResolvedTarget, o2: std.builtin.OptimizeMode) *std.Build.Module {
            return owner.createModule(.{ .root_source_file = dir.path(owner, path), .target = t2, .optimize = o2 });
        }
    }.make;
    const tables = module(b, src, "src/tables/tables.zig", target, optimize);
    const encoding = module(b, src, "src/encoding/encoding.zig", target, optimize);
    encoding.addImport("tables", tables);
    const linebreak = module(b, src, "src/linebreak/linebreak.zig", target, optimize);
    linebreak.addImport("tables", tables);
    linebreak.addImport("encoding", encoding);
    const bridge = diagnostic_sources.add("src/comparison_diagnostic.zig", "pub const scalar = @import(\"encoding\").scalar;\npub const line_break = @import(\"linebreak\");\npub const transitions = @import(\"tables\").line_break_machine_data;\n");
    const internal = b.createModule(.{ .root_source_file = bridge, .target = target, .optimize = optimize });
    internal.addImport("tables", tables);
    internal.addImport("encoding", encoding);
    internal.addImport("linebreak", linebreak);
    const diagnostic_options = b.addOptions();
    diagnostic_options.addOption(enum { off, scalar, auto, simd }, "wrap_fast_path", .auto);
    internal.addImport("build_options", diagnostic_options.createModule());
    const inputs = b.addWriteFiles();
    _ = inputs.addCopyDirectory(b.path("../texts"), "texts", .{});
    const verify_root = inputs.addCopyFile(b.path("verify-semantic.zig"), "verify-semantic.zig");
    const stats_root = inputs.addCopyFile(b.path("semantic-stats.zig"), "semantic-stats.zig");
    const diagnostic_root = inputs.addCopyFile(b.path("diagnostic.zig"), "diagnostic.zig");
    const verify_mod = b.createModule(.{ .root_source_file = verify_root, .target = target, .optimize = optimize });
    verify_mod.addImport("internal", internal);
    const verify = b.addExecutable(.{ .name = "verify-semantic", .root_module = verify_mod });
    const verify_run = b.addRunArtifact(verify);
    verify_run.addArg("--check");
    b.step("verify-semantic", "Check machine iterator/state protocol on all eight corpora").dependOn(&verify_run.step);
    const stats_mod = b.createModule(.{ .root_source_file = stats_root, .target = target, .optimize = optimize });
    stats_mod.addImport("internal", internal);
    const stats = b.addExecutable(.{ .name = "semantic-stats", .root_module = stats_mod });
    const stats_run = b.addRunArtifact(stats);
    stats_run.addArg("--stats");
    b.step("semantic-stats", "Report untimed semantic-machine action and lookahead counts").dependOn(&stats_run.step);
    const diagnostic = b.createModule(.{ .root_source_file = diagnostic_root, .target = target, .optimize = optimize });
    diagnostic.addImport("internal", internal);
    diagnostic.addImport("zunic", zunic.module("zunic"));
    const diag_exe = b.addExecutable(.{ .name = "line-break-diagnostic", .root_module = diagnostic });
    const install_diag = b.addInstallArtifact(diag_exe, .{});
    b.step("install-diagnostic", "Build and install the line-break diagnostic without running it").dependOn(&install_diag.step);
    const diag_run = b.addRunArtifact(diag_exe);
    diag_run.addArg("--bench");
    diag_run.step.dependOn(&install_diag.step);
    b.step("diagnostic", "Measure classification and rule processing separately").dependOn(&diag_run.step);
}
