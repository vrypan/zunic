const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zunic = b.dependency("zunic", .{ .target = target, .optimize = optimize });
    const uucode = b.dependency("uucode", .{
        .target = target,
        .optimize = optimize,
        // Configure only the data used by the comparable operations.
        .fields_0 = @as([]const []const u8, &.{
            "grapheme_break",
            "grapheme_break_no_control",
            "east_asian_width",
            "is_emoji_presentation",
            "is_emoji_vs_base",
            "is_emoji_modifier",
            "is_emoji_modifier_base",
            "is_emoji",
            "is_emoji_component",
            "case_folding_full",
            "wcwidth_standalone",
            "wcwidth_zero_in_grapheme",
        }),
        .fields_1 = @as([]const []const u8, &.{"simple_uppercase_mapping"}),
        .fields_2 = @as([]const []const u8, &.{"simple_lowercase_mapping"}),
        .fields_3 = @as([]const []const u8, &.{"simple_titlecase_mapping"}),
        .fields_4 = @as([]const []const u8, &.{
            "numeric_type",
            "numeric_value_decimal",
            "numeric_value_digit",
            "numeric_value_numeric",
        }),
        .fields_5 = @as([]const []const u8, &.{"canonical_combining_class"}),
        .fields_6 = @as([]const []const u8, &.{
            "decomposition_type",
            "decomposition_mapping",
        }),
    });

    // A separate uucode instance containing exactly the raw fields in
    // plans/031-ghostty-uucode-coverage.md. Keeping them in one generated
    // table matches the way Ghostty configures uucode and avoids retaining
    // benchmark-only numeric, decomposition, and simple-case data.
    const ghostty_uucode = b.dependency("uucode", .{
        .target = target,
        .optimize = optimize,
        .fields_0 = @as([]const []const u8, &.{
            "general_category",
            "east_asian_width",
            "is_emoji_presentation",
            "case_folding_full",
            "wcwidth_standalone",
            "wcwidth_zero_in_grapheme",
            "grapheme_break_no_control",
            "grapheme_break",
            "is_emoji_vs_base",
            "is_emoji_modifier",
            "is_emoji_modifier_base",
        }),
    });

    const generated = b.addWriteFiles();
    const benchmark_source = generated.addCopyFile(b.path("src/benchmark.zig"), "benchmark.zig");
    _ = generated.addCopyDirectory(b.path("../bench-vs-rust/texts"), "texts", .{});
    _ = generated.addCopyFile(b.path("texts/features.txt"), "texts/features.txt");

    const Peer = struct {
        name: []const u8,
        source: []const u8,
        import_name: []const u8,
        import_module: *std.Build.Module,
    };
    const peers = [_]Peer{
        .{ .name = "zunic-bench", .source = "src/zunic.zig", .import_name = "zunic", .import_module = zunic.module("zunic") },
        .{ .name = "uucode-bench", .source = "src/uucode.zig", .import_name = "uucode", .import_module = uucode.module("uucode") },
    };

    const test_step = b.step("test", "Run both peer adapters against the shared harness");
    for (peers) |peer| {
        const adapter = b.createModule(.{ .root_source_file = b.path(peer.source), .target = target, .optimize = optimize });
        adapter.addImport(peer.import_name, peer.import_module);

        const module = b.createModule(.{ .root_source_file = benchmark_source, .target = target, .optimize = optimize });
        module.addImport("peer", adapter);
        const executable = b.addExecutable(.{ .name = peer.name, .root_module = module });
        b.installArtifact(executable);

        const tests = b.addTest(.{ .root_module = module });
        test_step.dependOn(&b.addRunArtifact(tests).step);
    }

    const size_step = b.step("ghostty-size", "Build stripped Ghostty Unicode coverage binaries");
    const SizePeer = struct {
        name: []const u8,
        source: []const u8,
        import_name: []const u8,
        import_module: ?*std.Build.Module,
    };
    const size_peers = [_]SizePeer{
        .{ .name = "ghostty-size-control", .source = "src/ghostty_size_control.zig", .import_name = "coverage", .import_module = null },
        .{ .name = "ghostty-size-zunic", .source = "src/ghostty_size_zunic.zig", .import_name = "zunic", .import_module = zunic.module("zunic") },
        .{ .name = "ghostty-size-uucode", .source = "src/ghostty_size_uucode.zig", .import_name = "uucode", .import_module = ghostty_uucode.module("uucode") },
    };
    for (size_peers) |peer| {
        const module = b.createModule(.{
            .root_source_file = b.path(peer.source),
            .target = target,
            .optimize = optimize,
            .strip = true,
        });
        if (peer.import_module) |import_module|
            module.addImport(peer.import_name, import_module);
        const executable = b.addExecutable(.{ .name = peer.name, .root_module = module });
        size_step.dependOn(&b.addInstallArtifact(executable, .{}).step);
    }
}
