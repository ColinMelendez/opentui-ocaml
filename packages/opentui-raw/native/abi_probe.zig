const std = @import("std");
const opentui = @import("opentui");
const yoga = opentui.native_yoga;
const span_feed = opentui.native_span_feed;

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

    expectSize(yoga.ExternalYogaLayout, 24, "ExternalYogaLayout");
    expectOffset(yoga.ExternalYogaLayout, "left", 0, "ExternalYogaLayout.left");
    expectOffset(yoga.ExternalYogaLayout, "top", 4, "ExternalYogaLayout.top");
    expectOffset(yoga.ExternalYogaLayout, "right", 8, "ExternalYogaLayout.right");
    expectOffset(yoga.ExternalYogaLayout, "bottom", 12, "ExternalYogaLayout.bottom");
    expectOffset(yoga.ExternalYogaLayout, "width", 16, "ExternalYogaLayout.width");
    expectOffset(yoga.ExternalYogaLayout, "height", 20, "ExternalYogaLayout.height");

    expectSize(span_feed.Options, 24, "SpanFeed.Options");
    expectOffset(span_feed.Options, "chunk_size", 0, "SpanFeed.Options.chunk_size");
    expectOffset(span_feed.Options, "initial_chunks", 4, "SpanFeed.Options.initial_chunks");
    expectOffset(span_feed.Options, "max_bytes", 8, "SpanFeed.Options.max_bytes");
    expectOffset(span_feed.Options, "growth_policy", 16, "SpanFeed.Options.growth_policy");
    expectOffset(span_feed.Options, "auto_commit_on_full", 17, "SpanFeed.Options.auto_commit_on_full");
    expectOffset(span_feed.Options, "span_queue_capacity", 20, "SpanFeed.Options.span_queue_capacity");

    expectSize(span_feed.Stats, 24, "SpanFeed.Stats");
    expectOffset(span_feed.Stats, "bytes_written", 0, "SpanFeed.Stats.bytes_written");
    expectOffset(span_feed.Stats, "spans_committed", 8, "SpanFeed.Stats.spans_committed");
    expectOffset(span_feed.Stats, "chunks", 16, "SpanFeed.Stats.chunks");
    expectOffset(span_feed.Stats, "pending_spans", 20, "SpanFeed.Stats.pending_spans");

    expectSize(span_feed.SpanInfo, 24, "SpanFeed.SpanInfo");
    expectOffset(span_feed.SpanInfo, "chunk_ptr", 0, "SpanFeed.SpanInfo.chunk_ptr");
    expectOffset(span_feed.SpanInfo, "offset", 8, "SpanFeed.SpanInfo.offset");
    expectOffset(span_feed.SpanInfo, "len", 12, "SpanFeed.SpanInfo.len");
    expectOffset(span_feed.SpanInfo, "chunk_index", 16, "SpanFeed.SpanInfo.chunk_index");
    expectOffset(span_feed.SpanInfo, "reserved", 20, "SpanFeed.SpanInfo.reserved");

    expectSize(span_feed.ReserveInfo, 16, "SpanFeed.ReserveInfo");
    expectOffset(span_feed.ReserveInfo, "ptr", 0, "SpanFeed.ReserveInfo.ptr");
    expectOffset(span_feed.ReserveInfo, "len", 8, "SpanFeed.ReserveInfo.len");
    expectOffset(span_feed.ReserveInfo, "reserved", 12, "SpanFeed.ReserveInfo.reserved");

    expectType(
        @TypeOf(opentui.createNativeSpanFeed),
        fn (?*const span_feed.Options) callconv(.c) ?*span_feed.Stream,
        "createNativeSpanFeed",
    );
    expectType(
        @TypeOf(span_feed.attachNativeSpanFeed),
        fn (?*span_feed.Stream) callconv(.c) i32,
        "attachNativeSpanFeed",
    );
    expectType(
        @TypeOf(span_feed.streamClose),
        fn (?*span_feed.Stream) callconv(.c) i32,
        "streamClose",
    );
    expectType(
        @TypeOf(span_feed.destroyNativeSpanFeed),
        fn (?*span_feed.Stream) callconv(.c) void,
        "destroyNativeSpanFeed",
    );
    expectType(
        @TypeOf(span_feed.streamWrite),
        fn (?*span_feed.Stream, ?[*]const u8, u32) callconv(.c) i32,
        "streamWrite",
    );
    expectType(
        @TypeOf(span_feed.streamCommit),
        fn (?*span_feed.Stream) callconv(.c) i32,
        "streamCommit",
    );
    expectType(
        @TypeOf(span_feed.streamReserve),
        fn (?*span_feed.Stream, u32, ?*span_feed.ReserveInfo) callconv(.c) i32,
        "streamReserve",
    );
    expectType(
        @TypeOf(span_feed.streamCommitReserved),
        fn (?*span_feed.Stream, u32) callconv(.c) i32,
        "streamCommitReserved",
    );
    expectType(
        @TypeOf(span_feed.streamSetOptions),
        fn (?*span_feed.Stream, ?*const span_feed.Options) callconv(.c) i32,
        "streamSetOptions",
    );
    expectType(
        @TypeOf(span_feed.streamGetStats),
        fn (?*span_feed.Stream, ?*span_feed.Stats) callconv(.c) i32,
        "streamGetStats",
    );
    expectType(
        @TypeOf(span_feed.streamDrainSpans),
        fn (?*span_feed.Stream, ?*span_feed.SpanInfo, u32) callconv(.c) u32,
        "streamDrainSpans",
    );
    expectType(
        @TypeOf(span_feed.streamSetCallback),
        fn (?*span_feed.Stream, ?*const span_feed.CallbackFn) callconv(.c) void,
        "streamSetCallback",
    );

    expectType(
        @TypeOf(yoga.yogaConfigCreate),
        fn () callconv(.c) yoga.YGConfigRef,
        "yogaConfigCreate",
    );
    expectType(
        @TypeOf(yoga.yogaConfigFree),
        fn (yoga.YGConfigRef) callconv(.c) void,
        "yogaConfigFree",
    );
    expectType(
        @TypeOf(yoga.yogaNodeCreateWithConfig),
        fn (yoga.YGConfigConstRef) callconv(.c) yoga.YGNodeRef,
        "yogaNodeCreateWithConfig",
    );
    expectType(
        @TypeOf(yoga.yogaNodeFreeRecursive),
        fn (yoga.YGNodeRef) callconv(.c) void,
        "yogaNodeFreeRecursive",
    );
    expectType(
        @TypeOf(yoga.yogaNodeInsertChild),
        fn (yoga.YGNodeRef, yoga.YGNodeRef, u32) callconv(.c) void,
        "yogaNodeInsertChild",
    );
    expectType(
        @TypeOf(yoga.yogaNodeGetChildCount),
        fn (yoga.YGNodeConstRef) callconv(.c) u32,
        "yogaNodeGetChildCount",
    );
    expectType(
        @TypeOf(yoga.yogaNodeCalculateLayout),
        fn (yoga.YGNodeRef, f32, f32, u32) callconv(.c) void,
        "yogaNodeCalculateLayout",
    );
    expectType(
        @TypeOf(yoga.yogaNodeGetComputedLayout),
        fn (yoga.YGNodeConstRef, *yoga.ExternalYogaLayout) callconv(.c) void,
        "yogaNodeGetComputedLayout",
    );
    expectType(
        @TypeOf(yoga.yogaNodeStyleSetValue),
        fn (yoga.YGNodeRef, u32, u32, u32, f32) callconv(.c) void,
        "yogaNodeStyleSetValue",
    );

    expectSize(opentui.ExternalCapabilities, 64, "ExternalCapabilities");
    expectOffset(opentui.ExternalCapabilities, "kitty_keyboard", 0, "ExternalCapabilities.kitty_keyboard");
    expectOffset(opentui.ExternalCapabilities, "unicode", 4, "ExternalCapabilities.unicode");
    expectOffset(opentui.ExternalCapabilities, "multiplexer", 18, "ExternalCapabilities.multiplexer");
    expectOffset(opentui.ExternalCapabilities, "image_protocol", 19, "ExternalCapabilities.image_protocol");
    expectOffset(opentui.ExternalCapabilities, "term_name_ptr", 24, "ExternalCapabilities.term_name_ptr");
    expectOffset(opentui.ExternalCapabilities, "term_name_len", 32, "ExternalCapabilities.term_name_len");
    expectOffset(opentui.ExternalCapabilities, "term_version_ptr", 40, "ExternalCapabilities.term_version_ptr");
    expectOffset(opentui.ExternalCapabilities, "term_version_len", 48, "ExternalCapabilities.term_version_len");
    expectOffset(opentui.ExternalCapabilities, "term_from_xtversion", 56, "ExternalCapabilities.term_from_xtversion");
    expectOffset(opentui.ExternalCapabilities, "osc52_support", 57, "ExternalCapabilities.osc52_support");

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
    expectType(
        @TypeOf(opentui.getTerminalCapabilities),
        fn (opentui.NativeHandle, *opentui.ExternalCapabilities) callconv(.c) void,
        "getTerminalCapabilities",
    );
    expectType(
        @TypeOf(opentui.processCapabilityResponse),
        fn (opentui.NativeHandle, ?[*]const u8, u32) callconv(.c) void,
        "processCapabilityResponse",
    );

    expectType(
        @TypeOf(span_feed.streamCancelReserved),
        fn (?*span_feed.Stream) callconv(.c) i32,
        "streamCancelReserved",
    );
    expectType(
        @TypeOf(span_feed.streamMarkSpanConsumed),
        fn (?*span_feed.Stream, ?*const span_feed.SpanInfo) callconv(.c) i32,
        "streamMarkSpanConsumed",
    );
}

export fn opentui_phase1_abi_probe_marker() void {}
