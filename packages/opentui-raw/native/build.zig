const std = @import("std");

const default_source_root = "../../../vendor/opentui/packages/core/src/zig";

fn addUpstreamImports(
    b: *std.Build,
    module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    source_root: []const u8,
) void {
    const build_options = b.addOptions();
    build_options.addOption(bool, "gpa_safe_stats", false);
    module.addOptions("build_options", build_options);

    const miniaudio_translate = b.addTranslateC(.{
        .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ source_root, "vendor/miniaudio/miniaudio.h" }) },
        .target = target,
        .optimize = optimize,
    });
    miniaudio_translate.addIncludePath(.{ .cwd_relative = source_root });
    module.addImport("miniaudio", miniaudio_translate.createModule());

    const yoga_dep = b.dependency("yoga", .{});
    const yoga_translate = b.addTranslateC(.{
        .root_source_file = yoga_dep.path("yoga/Yoga.h"),
        .target = target,
        .optimize = optimize,
    });
    yoga_translate.addIncludePath(yoga_dep.path(""));
    module.addImport("yoga", yoga_translate.createModule());

    const ghostty_vt_options = b.addOptions();
    ghostty_vt_options.addOption(bool, "available", false);
    module.addOptions("ghostty_vt_options", ghostty_vt_options);

    const uucode_dep = b.dependency("uucode", .{
        .target = target,
        .optimize = optimize,
        .fields = @as([]const []const u8, &.{
            "grapheme_break",
            "east_asian_width",
            "general_category",
            "is_emoji_presentation",
        }),
    });
    module.addImport("uucode", uucode_dep.module("uucode"));
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const source_root = b.option([]const u8, "source-root", "Pinned OpenTUI source root used by the ABI probe") orelse default_source_root;

    const upstream_module = b.createModule(.{
        .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ source_root, "lib.zig" }) },
        .target = target,
        .optimize = optimize,
    });
    addUpstreamImports(b, upstream_module, target, optimize, source_root);

    const probe_module = b.createModule(.{
        .root_source_file = b.path("abi_probe.zig"),
        .target = target,
        .optimize = optimize,
    });
    probe_module.addImport("opentui", upstream_module);

    const probe = b.addObject(.{
        .name = "opentui_abi_probe",
        .root_module = probe_module,
    });
    b.default_step.dependOn(&probe.step);
}
