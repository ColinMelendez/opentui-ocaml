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

fn expectEnumValue(comptime actual: anytype, comptime expected: comptime_int, comptime name: []const u8) void {
    if (@intFromEnum(actual) != expected) {
        @compileError(name ++ " has an unexpected ABI value");
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

    expectEnumValue(yoga.YogaEnumKind.direction, 0, "YogaEnumKind.direction");
    expectEnumValue(yoga.YogaEnumKind.flex_direction, 1, "YogaEnumKind.flex_direction");
    expectEnumValue(yoga.YogaEnumKind.justify_content, 2, "YogaEnumKind.justify_content");
    expectEnumValue(yoga.YogaEnumKind.align_content, 3, "YogaEnumKind.align_content");
    expectEnumValue(yoga.YogaEnumKind.align_items, 4, "YogaEnumKind.align_items");
    expectEnumValue(yoga.YogaEnumKind.align_self, 5, "YogaEnumKind.align_self");
    expectEnumValue(yoga.YogaEnumKind.position_type, 6, "YogaEnumKind.position_type");
    expectEnumValue(yoga.YogaEnumKind.flex_wrap, 7, "YogaEnumKind.flex_wrap");
    expectEnumValue(yoga.YogaEnumKind.overflow, 8, "YogaEnumKind.overflow");
    expectEnumValue(yoga.YogaEnumKind.display, 9, "YogaEnumKind.display");
    expectEnumValue(yoga.YogaEnumKind.box_sizing, 10, "YogaEnumKind.box_sizing");

    expectEnumValue(yoga.YogaFloatKind.flex, 0, "YogaFloatKind.flex");
    expectEnumValue(yoga.YogaFloatKind.flex_grow, 1, "YogaFloatKind.flex_grow");
    expectEnumValue(yoga.YogaFloatKind.flex_shrink, 2, "YogaFloatKind.flex_shrink");
    expectEnumValue(yoga.YogaFloatKind.aspect_ratio, 3, "YogaFloatKind.aspect_ratio");

    expectEnumValue(yoga.YogaValueKind.width, 0, "YogaValueKind.width");
    expectEnumValue(yoga.YogaValueKind.height, 1, "YogaValueKind.height");
    expectEnumValue(yoga.YogaValueKind.min_width, 2, "YogaValueKind.min_width");
    expectEnumValue(yoga.YogaValueKind.min_height, 3, "YogaValueKind.min_height");
    expectEnumValue(yoga.YogaValueKind.max_width, 4, "YogaValueKind.max_width");
    expectEnumValue(yoga.YogaValueKind.max_height, 5, "YogaValueKind.max_height");
    expectEnumValue(yoga.YogaValueKind.flex_basis, 6, "YogaValueKind.flex_basis");
    expectEnumValue(yoga.YogaValueKind.margin, 7, "YogaValueKind.margin");
    expectEnumValue(yoga.YogaValueKind.padding, 8, "YogaValueKind.padding");
    expectEnumValue(yoga.YogaValueKind.position, 9, "YogaValueKind.position");
    expectEnumValue(yoga.YogaValueKind.gap, 10, "YogaValueKind.gap");

    expectEnumValue(yoga.YogaUnit.undefined, 0, "YogaUnit.undefined");
    expectEnumValue(yoga.YogaUnit.point, 1, "YogaUnit.point");
    expectEnumValue(yoga.YogaUnit.percent, 2, "YogaUnit.percent");
    expectEnumValue(yoga.YogaUnit.auto, 3, "YogaUnit.auto");

    expectEnumValue(yoga.YogaDirection.inherit, 0, "YogaDirection.inherit");
    expectEnumValue(yoga.YogaDirection.ltr, 1, "YogaDirection.ltr");
    expectEnumValue(yoga.YogaDirection.rtl, 2, "YogaDirection.rtl");

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
        @TypeOf(yoga.yogaNodeCreateForOpenTUI),
        fn () callconv(.c) yoga.YGNodeRef,
        "yogaNodeCreateForOpenTUI",
    );
    expectType(
        @TypeOf(yoga.yogaNodeFree),
        fn (yoga.YGNodeRef) callconv(.c) void,
        "yogaNodeFree",
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
        @TypeOf(yoga.yogaNodeRemoveChild),
        fn (yoga.YGNodeRef, yoga.YGNodeRef) callconv(.c) void,
        "yogaNodeRemoveChild",
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
        @TypeOf(yoga.yogaNodeSetMeasureFunc),
        fn (yoga.YGNodeRef, bool) callconv(.c) void,
        "yogaNodeSetMeasureFunc",
    );
    expectType(
        @TypeOf(yoga.yogaNodeUnsetMeasureFunc),
        fn (yoga.YGNodeRef) callconv(.c) void,
        "yogaNodeUnsetMeasureFunc",
    );
    expectType(
        @TypeOf(yoga.yogaNodeHasMeasureFunc),
        fn (yoga.YGNodeConstRef) callconv(.c) bool,
        "yogaNodeHasMeasureFunc",
    );
    expectType(
        @TypeOf(yoga.yogaSetMeasureCallback),
        fn (?*const anyopaque) callconv(.c) void,
        "yogaSetMeasureCallback",
    );
    expectType(
        @TypeOf(yoga.yogaStoreMeasureResult),
        fn (f32, f32) callconv(.c) void,
        "yogaStoreMeasureResult",
    );
    expectType(
        @TypeOf(yoga.yogaNodeIsDirty),
        fn (yoga.YGNodeConstRef) callconv(.c) bool,
        "yogaNodeIsDirty",
    );
    expectType(
        @TypeOf(yoga.yogaNodeMarkDirty),
        fn (yoga.YGNodeRef) callconv(.c) void,
        "yogaNodeMarkDirty",
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
    expectType(
        @TypeOf(yoga.yogaNodeStyleSetEnum),
        fn (yoga.YGNodeRef, u32, u32) callconv(.c) void,
        "yogaNodeStyleSetEnum",
    );
    expectType(
        @TypeOf(yoga.yogaNodeStyleSetFloat),
        fn (yoga.YGNodeRef, u32, f32) callconv(.c) void,
        "yogaNodeStyleSetFloat",
    );
    expectType(
        @TypeOf(yoga.yogaNodeStyleSetBorder),
        fn (yoga.YGNodeRef, u32, f32) callconv(.c) void,
        "yogaNodeStyleSetBorder",
    );

    expectSize(opentui.ExternalMeasureResult, 8, "ExternalMeasureResult");
    expectOffset(opentui.ExternalMeasureResult, "line_count", 0, "ExternalMeasureResult.line_count");
    expectOffset(opentui.ExternalMeasureResult, "width_cols_max", 4, "ExternalMeasureResult.width_cols_max");
    expectType(
        @TypeOf(opentui.createNativeRenderable),
        fn () callconv(.c) opentui.NativeHandle,
        "createNativeRenderable",
    );
    expectType(
        @TypeOf(opentui.destroyNativeRenderable),
        fn (opentui.NativeHandle) callconv(.c) void,
        "destroyNativeRenderable",
    );
    expectType(
        @TypeOf(opentui.nativeRenderableAttachYogaNode),
        fn (opentui.NativeHandle, yoga.YGNodeRef) callconv(.c) bool,
        "nativeRenderableAttachYogaNode",
    );
    expectType(
        @TypeOf(opentui.nativeRenderableSetMeasureTarget),
        fn (opentui.NativeHandle, u32, opentui.NativeHandle) callconv(.c) bool,
        "nativeRenderableSetMeasureTarget",
    );
    expectType(
        @TypeOf(opentui.createTextBuffer),
        fn (u8) callconv(.c) opentui.NativeHandle,
        "createTextBuffer",
    );
    expectType(
        @TypeOf(opentui.destroyTextBuffer),
        fn (opentui.NativeHandle) callconv(.c) void,
        "destroyTextBuffer",
    );
    expectType(
        @TypeOf(opentui.textBufferGetLength),
        fn (opentui.NativeHandle) callconv(.c) u32,
        "textBufferGetLength",
    );
    expectType(
        @TypeOf(opentui.textBufferGetByteSize),
        fn (opentui.NativeHandle) callconv(.c) u32,
        "textBufferGetByteSize",
    );
    expectType(
        @TypeOf(opentui.textBufferReset),
        fn (opentui.NativeHandle) callconv(.c) void,
        "textBufferReset",
    );
    expectType(
        @TypeOf(opentui.textBufferClear),
        fn (opentui.NativeHandle) callconv(.c) void,
        "textBufferClear",
    );
    expectType(
        @TypeOf(opentui.textBufferAppend),
        fn (opentui.NativeHandle, ?[*]const u8, u32) callconv(.c) void,
        "textBufferAppend",
    );
    expectType(
        @TypeOf(opentui.textBufferRegisterMemBuffer),
        fn (opentui.NativeHandle, ?[*]const u8, u32, bool) callconv(.c) u16,
        "textBufferRegisterMemBuffer",
    );
    expectType(
        @TypeOf(opentui.textBufferReplaceMemBuffer),
        fn (opentui.NativeHandle, u8, ?[*]const u8, u32, bool) callconv(.c) bool,
        "textBufferReplaceMemBuffer",
    );
    expectType(
        @TypeOf(opentui.textBufferSetTextFromMem),
        fn (opentui.NativeHandle, u8) callconv(.c) void,
        "textBufferSetTextFromMem",
    );
    expectType(@TypeOf(opentui.textBufferSetDefaultFg), fn (opentui.NativeHandle, ?[*]const u16) callconv(.c) void, "textBufferSetDefaultFg");
    expectType(@TypeOf(opentui.textBufferSetDefaultBg), fn (opentui.NativeHandle, ?[*]const u16) callconv(.c) void, "textBufferSetDefaultBg");
    expectType(@TypeOf(opentui.textBufferSetDefaultAttributes), fn (opentui.NativeHandle, ?[*]const u32) callconv(.c) void, "textBufferSetDefaultAttributes");
    expectType(@TypeOf(opentui.textBufferResetDefaults), fn (opentui.NativeHandle) callconv(.c) void, "textBufferResetDefaults");
    expectType(@TypeOf(opentui.textBufferClearAllHighlights), fn (opentui.NativeHandle) callconv(.c) void, "textBufferClearAllHighlights");
    expectType(@TypeOf(opentui.textBufferAddHighlightByCharRange), fn (opentui.NativeHandle, [*]const opentui.ExternalHighlight) callconv(.c) void, "textBufferAddHighlightByCharRange");
    expectType(@TypeOf(opentui.textBufferAddHighlight), fn (opentui.NativeHandle, u32, [*]const opentui.ExternalHighlight) callconv(.c) void, "textBufferAddHighlight");
    expectType(@TypeOf(opentui.textBufferRemoveHighlightsByRef), fn (opentui.NativeHandle, u16) callconv(.c) void, "textBufferRemoveHighlightsByRef");
    expectType(@TypeOf(opentui.textBufferClearLineHighlights), fn (opentui.NativeHandle, u32) callconv(.c) void, "textBufferClearLineHighlights");
    expectType(@TypeOf(opentui.textBufferSetSyntaxStyle), fn (opentui.NativeHandle, opentui.NativeHandle) callconv(.c) bool, "textBufferSetSyntaxStyle");
    expectType(@TypeOf(opentui.createSyntaxStyle), fn () callconv(.c) opentui.NativeHandle, "createSyntaxStyle");
    expectType(@TypeOf(opentui.destroySyntaxStyle), fn (opentui.NativeHandle) callconv(.c) void, "destroySyntaxStyle");
    expectType(@TypeOf(opentui.syntaxStyleRegister), fn (opentui.NativeHandle, ?[*]const u8, u32, ?[*]const u16, ?[*]const u16, u32) callconv(.c) u32, "syntaxStyleRegister");
    expectType(@TypeOf(opentui.syntaxStyleResolveByName), fn (opentui.NativeHandle, ?[*]const u8, u32) callconv(.c) u32, "syntaxStyleResolveByName");
    expectType(@TypeOf(opentui.syntaxStyleGetStyleCount), fn (opentui.NativeHandle) callconv(.c) u32, "syntaxStyleGetStyleCount");
    expectType(
        @TypeOf(opentui.createTextBufferView),
        fn (opentui.NativeHandle) callconv(.c) opentui.NativeHandle,
        "createTextBufferView",
    );
    expectType(
        @TypeOf(opentui.destroyTextBufferView),
        fn (opentui.NativeHandle) callconv(.c) void,
        "destroyTextBufferView",
    );
    expectType(
        @TypeOf(opentui.textBufferViewSetWrapWidth),
        fn (opentui.NativeHandle, u32) callconv(.c) void,
        "textBufferViewSetWrapWidth",
    );
    expectType(
        @TypeOf(opentui.textBufferViewSetWrapMode),
        fn (opentui.NativeHandle, u8) callconv(.c) void,
        "textBufferViewSetWrapMode",
    );
    expectType(
        @TypeOf(opentui.textBufferViewSetFirstLineOffset),
        fn (opentui.NativeHandle, u32) callconv(.c) void,
        "textBufferViewSetFirstLineOffset",
    );
    expectType(
        @TypeOf(opentui.textBufferViewMeasureForDimensions),
        fn (opentui.NativeHandle, u32, u32, *opentui.ExternalMeasureResult) callconv(.c) bool,
        "textBufferViewMeasureForDimensions",
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
        @TypeOf(opentui.resizeRenderer),
        fn (opentui.NativeHandle, u32, u32) callconv(.c) void,
        "resizeRenderer",
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
        @TypeOf(opentui.render),
        fn (opentui.NativeHandle, bool) callconv(.c) u8,
        "render",
    );
    expectType(
        @TypeOf(opentui.addToHitGrid),
        fn (opentui.NativeHandle, i32, i32, u32, u32, u32) callconv(.c) void,
        "addToHitGrid",
    );
    expectType(
        @TypeOf(opentui.clearCurrentHitGrid),
        fn (opentui.NativeHandle) callconv(.c) void,
        "clearCurrentHitGrid",
    );
    expectType(
        @TypeOf(opentui.clearNextHitGrid),
        fn (opentui.NativeHandle) callconv(.c) void,
        "clearNextHitGrid",
    );
    expectType(
        @TypeOf(opentui.hitGridPushScissorRect),
        fn (opentui.NativeHandle, i32, i32, u32, u32) callconv(.c) void,
        "hitGridPushScissorRect",
    );
    expectType(
        @TypeOf(opentui.hitGridPopScissorRect),
        fn (opentui.NativeHandle) callconv(.c) void,
        "hitGridPopScissorRect",
    );
    expectType(
        @TypeOf(opentui.hitGridClearScissorRects),
        fn (opentui.NativeHandle) callconv(.c) void,
        "hitGridClearScissorRects",
    );
    expectType(
        @TypeOf(opentui.addToCurrentHitGridClipped),
        fn (opentui.NativeHandle, i32, i32, u32, u32, u32) callconv(.c) void,
        "addToCurrentHitGridClipped",
    );
    expectType(
        @TypeOf(opentui.checkHit),
        fn (opentui.NativeHandle, u32, u32) callconv(.c) u32,
        "checkHit",
    );
    expectType(
        @TypeOf(opentui.getHitGridDirty),
        fn (opentui.NativeHandle) callconv(.c) bool,
        "getHitGridDirty",
    );
    const render_status = @typeInfo(@TypeOf(opentui.CliRenderer.render)).@"fn".return_type.?;
    expectEnumValue(@as(render_status, .rendered), 0, "RenderStatus.rendered");
    expectEnumValue(@as(render_status, .skipped), 1, "RenderStatus.skipped");
    expectEnumValue(@as(render_status, .failed), 2, "RenderStatus.failed");
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
        @TypeOf(opentui.createOptimizedBuffer),
        fn (u32, u32, bool, u8, ?[*]const u8, u32) callconv(.c) opentui.NativeHandle,
        "createOptimizedBuffer",
    );
    expectType(
        @TypeOf(opentui.destroyOptimizedBuffer),
        fn (opentui.NativeHandle) callconv(.c) void,
        "destroyOptimizedBuffer",
    );
    expectType(
        @TypeOf(opentui.destroyFrameBuffer),
        fn (opentui.NativeHandle) callconv(.c) void,
        "destroyFrameBuffer",
    );
    expectType(
        @TypeOf(opentui.drawFrameBuffer),
        fn (opentui.NativeHandle, i32, i32, opentui.NativeHandle, u32, u32, u32, u32) callconv(.c) void,
        "drawFrameBuffer",
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
        @TypeOf(opentui.bufferDrawBox),
        fn (opentui.NativeHandle, i32, i32, u32, u32, [*]const u32, u32, [*]const u16, [*]const u16, [*]const u16, ?[*]const u8, u32, ?[*]const u8, u32) callconv(.c) void,
        "bufferDrawBox",
    );
    expectType(
        @TypeOf(opentui.bufferSetCell),
        fn (opentui.NativeHandle, u32, u32, u32, [*]const u16, [*]const u16, u32) callconv(.c) void,
        "bufferSetCell",
    );
    expectType(
        @TypeOf(opentui.bufferSetCellWithAlphaBlending),
        fn (opentui.NativeHandle, u32, u32, u32, [*]const u16, [*]const u16, u32) callconv(.c) void,
        "bufferSetCellWithAlphaBlending",
    );
    expectType(
        @TypeOf(opentui.bufferFillRect),
        fn (opentui.NativeHandle, u32, u32, u32, u32, [*]const u16) callconv(.c) void,
        "bufferFillRect",
    );
    expectType(
        @TypeOf(opentui.bufferResize),
        fn (opentui.NativeHandle, u32, u32) callconv(.c) void,
        "bufferResize",
    );
    expectType(
        @TypeOf(opentui.bufferDrawGrid),
        fn (opentui.NativeHandle, [*]const u32, [*]const u16, [*]const u16, [*]const i32, u32, [*]const i32, u32, *const opentui.ExternalGridDrawOptions) callconv(.c) void,
        "bufferDrawGrid",
    );
    expectType(
        @TypeOf(opentui.bufferDrawTextBufferView),
        fn (opentui.NativeHandle, opentui.NativeHandle, i32, i32) callconv(.c) void,
        "bufferDrawTextBufferView",
    );
    expectType(
        @TypeOf(opentui.bufferDrawGrid),
        fn (opentui.NativeHandle, [*]const u32, [*]const u16, [*]const u16, [*]const i32, u32, [*]const i32, u32, *const opentui.ExternalGridDrawOptions) callconv(.c) void,
        "bufferDrawGrid",
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
