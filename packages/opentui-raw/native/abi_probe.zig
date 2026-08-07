const std = @import("std");
const opentui = @import("opentui");

var io_threaded: std.Io.Threaded = .init_single_threaded;
pub const io = io_threaded.io();

fn expectType(comptime actual: type, comptime expected: type, comptime name: []const u8) void {
    if (actual != expected) {
        @compileError(name ++ " has an unexpected ABI type");
    }
}

fn expectSize(comptime actual: type, comptime expected: comptime_int, comptime name: []const u8) void {
    if (@sizeOf(actual) != expected) {
        @compileError(name ++ " has an unexpected ABI size");
    }
}

fn expectOffset(
    comptime struct_type: type,
    comptime field_name: []const u8,
    comptime expected: comptime_int,
    comptime name: []const u8,
) void {
    if (@offsetOf(struct_type, field_name) != expected) {
        @compileError(name ++ " has an unexpected ABI offset");
    }
}

comptime {
    expectSize(opentui.NativeHandle, 4, "NativeHandle");
    expectType(
        opentui.NativeHandle,
        u32,
        "NativeHandle",
    );

    expectSize(bool, 1, "bool");
    expectSize(opentui.RGBA, 8, "RGBA");
    expectType(opentui.RGBA, [4]u16, "RGBA");

    expectType(
        @TypeOf(opentui.createEventSink),
        fn (?*const fn ([*]const u8, u32, [*]const u8, u32) callconv(.c) void) callconv(.c) opentui.NativeHandle,
        "createEventSink",
    );
    expectType(
        @TypeOf(opentui.destroyEventSink),
        fn (opentui.NativeHandle) callconv(.c) void,
        "destroyEventSink",
    );
    expectType(
        @TypeOf(opentui.createEditBuffer),
        fn (u8, opentui.NativeHandle) callconv(.c) opentui.NativeHandle,
        "createEditBuffer",
    );
    expectType(
        @TypeOf(opentui.destroyEditBuffer),
        fn (opentui.NativeHandle) callconv(.c) void,
        "destroyEditBuffer",
    );
    expectType(
        @TypeOf(opentui.editBufferInsertText),
        fn (opentui.NativeHandle, ?[*]const u8, u32) callconv(.c) void,
        "editBufferInsertText",
    );

    const create_renderer = @typeInfo(@TypeOf(opentui.createRenderer)).@"fn";
    expectType(create_renderer.params[0].type.?, u32, "createRenderer.width");
    expectType(create_renderer.params[1].type.?, u32, "createRenderer.height");
    expectType(create_renderer.params[2].type.?, u8, "createRenderer.destination");
    expectType(create_renderer.params[3].type.?, u8, "createRenderer.remote_mode");
    expectType(create_renderer.return_type.?, opentui.NativeHandle, "createRenderer.return");

    const create_span_feed = @typeInfo(@TypeOf(opentui.createNativeSpanFeed)).@"fn";
    expectType(create_renderer.params[4].type.?, create_span_feed.return_type.?, "createRenderer.feed");

    expectType(
        @TypeOf(opentui.setUseThread),
        fn (opentui.NativeHandle, bool) callconv(.c) void,
        "setUseThread",
    );
    expectType(
        @TypeOf(opentui.destroyRenderer),
        fn (opentui.NativeHandle) callconv(.c) void,
        "destroyRenderer",
    );
    expectType(
        @TypeOf(opentui.getCurrentBuffer),
        fn (opentui.NativeHandle) callconv(.c) opentui.NativeHandle,
        "getCurrentBuffer",
    );
    expectType(
        @TypeOf(opentui.getNextBuffer),
        fn (opentui.NativeHandle) callconv(.c) opentui.NativeHandle,
        "getNextBuffer",
    );
    expectType(
        @TypeOf(opentui.getBufferWidth),
        fn (opentui.NativeHandle) callconv(.c) u32,
        "getBufferWidth",
    );
    expectType(
        @TypeOf(opentui.getBufferHeight),
        fn (opentui.NativeHandle) callconv(.c) u32,
        "getBufferHeight",
    );

    expectType(
        @TypeOf(opentui.bufferClear),
        fn (opentui.NativeHandle, [*]const u16) callconv(.c) void,
        "bufferClear",
    );
    expectType(
        @TypeOf(opentui.bufferWriteResolvedChars),
        fn (opentui.NativeHandle, ?[*]u8, u32, bool) callconv(.c) u32,
        "bufferWriteResolvedChars",
    );
    expectType(
        @TypeOf(opentui.bufferDrawText),
        fn (opentui.NativeHandle, ?[*]const u8, u32, u32, u32, [*]const u16, ?[*]const u16, u32) callconv(.c) void,
        "bufferDrawText",
    );
    expectType(
        @TypeOf(opentui.bufferSetCell),
        fn (opentui.NativeHandle, u32, u32, u32, [*]const u16, [*]const u16, u32) callconv(.c) void,
        "bufferSetCell",
    );

    expectSize(opentui.ExternalBuildOptions, 2, "ExternalBuildOptions");
    expectOffset(opentui.ExternalBuildOptions, "gpa_safe_stats", 0, "ExternalBuildOptions.gpa_safe_stats");
    expectOffset(
        opentui.ExternalBuildOptions,
        "gpa_memory_limit_tracking",
        1,
        "ExternalBuildOptions.gpa_memory_limit_tracking",
    );

    expectSize(opentui.ExternalAllocatorStats, 40, "ExternalAllocatorStats");
    expectOffset(opentui.ExternalAllocatorStats, "total_requested_bytes", 0, "ExternalAllocatorStats.total_requested_bytes");
    expectOffset(opentui.ExternalAllocatorStats, "active_allocations", 8, "ExternalAllocatorStats.active_allocations");
    expectOffset(opentui.ExternalAllocatorStats, "small_allocations", 16, "ExternalAllocatorStats.small_allocations");
    expectOffset(opentui.ExternalAllocatorStats, "large_allocations", 24, "ExternalAllocatorStats.large_allocations");
    expectOffset(opentui.ExternalAllocatorStats, "requested_bytes_valid", 32, "ExternalAllocatorStats.requested_bytes_valid");

    expectSize(opentui.ExternalRenderStats, 56, "ExternalRenderStats");
    expectOffset(opentui.ExternalRenderStats, "last_frame_time", 0, "ExternalRenderStats.last_frame_time");
    expectOffset(opentui.ExternalRenderStats, "average_frame_time", 8, "ExternalRenderStats.average_frame_time");
    expectOffset(opentui.ExternalRenderStats, "render_time", 16, "ExternalRenderStats.render_time");
    expectOffset(opentui.ExternalRenderStats, "stdout_write_time", 24, "ExternalRenderStats.stdout_write_time");
    expectOffset(opentui.ExternalRenderStats, "frame_count", 32, "ExternalRenderStats.frame_count");
    expectOffset(opentui.ExternalRenderStats, "cells_updated", 40, "ExternalRenderStats.cells_updated");
    expectOffset(opentui.ExternalRenderStats, "average_cells_updated", 44, "ExternalRenderStats.average_cells_updated");
    expectOffset(opentui.ExternalRenderStats, "render_time_valid", 48, "ExternalRenderStats.render_time_valid");
    expectOffset(opentui.ExternalRenderStats, "stdout_write_time_valid", 49, "ExternalRenderStats.stdout_write_time_valid");

    expectType(
        @TypeOf(opentui.getAllocatorStats),
        fn (*opentui.ExternalAllocatorStats) callconv(.c) void,
        "getAllocatorStats",
    );
}

export fn opentui_phase1_abi_probe_marker() void {}
