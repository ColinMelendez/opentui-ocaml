#ifndef OPENTUI_RAW_ABI_H
#define OPENTUI_RAW_ABI_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef uint32_t opentui_native_handle;

enum opentui_render_status {
  OPENTUI_RENDER_STATUS_RENDERED = 0,
  OPENTUI_RENDER_STATUS_SKIPPED = 1,
  OPENTUI_RENDER_STATUS_FAILED = 2
};

typedef void (*opentui_event_callback)(
    const uint8_t *name_ptr,
    uint32_t name_len,
    const uint8_t *data_ptr,
    uint32_t data_len);

typedef struct opentui_external_build_options {
  bool gpa_safe_stats;
  bool gpa_memory_limit_tracking;
} opentui_external_build_options;

typedef struct opentui_external_allocator_stats {
  uint64_t total_requested_bytes;
  uint64_t active_allocations;
  uint64_t small_allocations;
  uint64_t large_allocations;
  bool requested_bytes_valid;
} opentui_external_allocator_stats;

typedef struct opentui_external_render_stats {
  double last_frame_time;
  double average_frame_time;
  double render_time;
  double stdout_write_time;
  uint64_t frame_count;
  uint32_t cells_updated;
  uint32_t average_cells_updated;
  bool render_time_valid;
  bool stdout_write_time_valid;
} opentui_external_render_stats;

typedef struct opentui_external_cursor_style_options {
  uint8_t style;
  uint8_t blinking;
  const uint16_t *color;
  uint8_t cursor;
} opentui_external_cursor_style_options;

typedef struct opentui_external_cursor_state {
  uint32_t x;
  uint32_t y;
  bool visible;
  uint8_t style;
  bool blinking;
  float r;
  float g;
  float b;
  float a;
} opentui_external_cursor_state;

typedef void *opentui_yoga_config_ref;
typedef const void *opentui_yoga_config_const_ref;
typedef void *opentui_yoga_node_ref;
typedef const void *opentui_yoga_node_const_ref;

typedef struct opentui_external_yoga_layout {
  float left;
  float top;
  float right;
  float bottom;
  float width;
  float height;
} opentui_external_yoga_layout;

typedef struct opentui_external_measure_result {
  uint32_t line_count;
  uint32_t width_cols_max;
} opentui_external_measure_result;

typedef struct opentui_external_line_info {
  const uint32_t *start_cols_ptr;
  uint32_t start_cols_len;
  const uint32_t *width_cols_ptr;
  uint32_t width_cols_len;
  const uint32_t *sources_ptr;
  uint32_t sources_len;
  const uint32_t *wraps_ptr;
  uint32_t wraps_len;
  uint32_t width_cols_max;
} opentui_external_line_info;

typedef struct opentui_external_styled_chunk {
  const uint8_t *text_ptr;
  size_t text_len;
  const uint16_t *fg_ptr;
  const uint16_t *bg_ptr;
  uint32_t attributes;
  const uint8_t *link_ptr;
  size_t link_len;
} opentui_external_styled_chunk;

typedef struct opentui_external_highlight {
  uint32_t start;
  uint32_t end;
  uint32_t style_id;
  uint8_t priority;
  uint16_t hl_ref;
} opentui_external_highlight;

typedef struct opentui_external_capabilities {
  bool kitty_keyboard;
  bool kitty_graphics;
  bool rgb;
  bool ansi256;
  uint8_t unicode;
  bool sgr_pixels;
  bool color_scheme_updates;
  bool explicit_width;
  bool scaled_text;
  bool sixel;
  bool focus_tracking;
  bool sync;
  bool bracketed_paste;
  bool hyperlinks;
  bool osc52;
  bool notifications;
  bool explicit_cursor_positioning;
  bool remote;
  uint8_t multiplexer;
  uint8_t image_protocol;
  const uint8_t *term_name_ptr;
  size_t term_name_len;
  const uint8_t *term_version_ptr;
  size_t term_version_len;
  bool term_from_xtversion;
  uint8_t osc52_support;
} opentui_external_capabilities;

typedef void *opentui_span_feed_ref;

typedef struct opentui_external_span_feed_options {
  uint32_t chunk_size;
  uint32_t initial_chunks;
  uint64_t max_bytes;
  uint8_t growth_policy;
  uint8_t auto_commit_on_full;
  uint32_t span_queue_capacity;
} opentui_external_span_feed_options;

typedef struct opentui_external_span_feed_stats {
  uint64_t bytes_written;
  uint64_t spans_committed;
  uint32_t chunks;
  uint32_t pending_spans;
} opentui_external_span_feed_stats;

typedef struct opentui_external_span_info {
  uintptr_t chunk_ptr;
  uint32_t offset;
  uint32_t len;
  uint32_t chunk_index;
  uint32_t reserved;
} opentui_external_span_info;

typedef struct opentui_external_reserve_info {
  uintptr_t ptr;
  uint32_t len;
  uint32_t reserved;
} opentui_external_reserve_info;

typedef void (*opentui_span_feed_callback)(
    uintptr_t stream_ptr,
    uint32_t event_id,
    uintptr_t arg0,
    uint64_t arg1);

opentui_native_handle createEventSink(opentui_event_callback callback);
void destroyEventSink(opentui_native_handle sink_handle);
opentui_native_handle createEditBuffer(uint8_t width_method, opentui_native_handle event_sink_handle);
void destroyEditBuffer(opentui_native_handle edit_buffer_handle);
void editBufferInsertText(
    opentui_native_handle edit_buffer_handle,
    const uint8_t *text,
    uint32_t text_len);

opentui_native_handle createRenderer(
    uint32_t width,
    uint32_t height,
    uint8_t buffered_destination_kind,
    uint8_t remote_mode,
    void *feed_ptr);
void setUseThread(opentui_native_handle renderer_handle, bool use_thread);
void resizeRenderer(
    opentui_native_handle renderer_handle,
    uint32_t width,
    uint32_t height);
void setBackgroundColor(
    opentui_native_handle renderer_handle,
    const uint16_t *color);
void setCursorPosition(
    opentui_native_handle renderer_handle,
    int32_t x,
    int32_t y,
    bool visible);
void setCursorColor(
    opentui_native_handle renderer_handle,
    const uint16_t *color);
void setCursorStyleOptions(
    opentui_native_handle renderer_handle,
    const opentui_external_cursor_style_options *options);
void getCursorState(
    opentui_native_handle renderer_handle,
    opentui_external_cursor_state *output);
void destroyRenderer(opentui_native_handle renderer_handle);
opentui_native_handle getCurrentBuffer(opentui_native_handle renderer_handle);
opentui_native_handle getNextBuffer(opentui_native_handle renderer_handle);
uint8_t render(opentui_native_handle renderer_handle, bool force);
void addToHitGrid(
    opentui_native_handle renderer_handle,
    int32_t x,
    int32_t y,
    uint32_t width,
    uint32_t height,
    uint32_t id);
void clearCurrentHitGrid(opentui_native_handle renderer_handle);
void hitGridPushScissorRect(
    opentui_native_handle renderer_handle,
    int32_t x,
    int32_t y,
    uint32_t width,
    uint32_t height);
void hitGridPopScissorRect(opentui_native_handle renderer_handle);
void hitGridClearScissorRects(opentui_native_handle renderer_handle);
void addToCurrentHitGridClipped(
    opentui_native_handle renderer_handle,
    int32_t x,
    int32_t y,
    uint32_t width,
    uint32_t height,
    uint32_t id);
uint32_t checkHit(
    opentui_native_handle renderer_handle,
    uint32_t x,
    uint32_t y);
bool getHitGridDirty(opentui_native_handle renderer_handle);

/* Local raw seam: the reference clears nextHitGrid while aborting a frame
 * before native render can perform its normal skipped/failed cleanup. */
void clearNextHitGrid(opentui_native_handle renderer_handle);

uint32_t getBufferWidth(opentui_native_handle buffer_handle);
uint32_t getBufferHeight(opentui_native_handle buffer_handle);
opentui_native_handle createOptimizedBuffer(
    uint32_t width,
    uint32_t height,
    bool respect_alpha,
    uint8_t width_method,
    const uint8_t *id_ptr,
    uint32_t id_len);
void destroyOptimizedBuffer(opentui_native_handle buffer_handle);
void destroyFrameBuffer(opentui_native_handle buffer_handle);
void drawFrameBuffer(
    opentui_native_handle target_handle,
    int32_t dest_x,
    int32_t dest_y,
    opentui_native_handle frame_buffer_handle,
    uint32_t source_x,
    uint32_t source_y,
    uint32_t source_width,
    uint32_t source_height);
void bufferClear(opentui_native_handle buffer_handle, const uint16_t *background);
uint32_t bufferWriteResolvedChars(
    opentui_native_handle buffer_handle,
    uint8_t *output,
    uint32_t output_len,
    bool add_line_breaks);
void bufferDrawText(
    opentui_native_handle buffer_handle,
    const uint8_t *text,
    uint32_t text_len,
    uint32_t x,
    uint32_t y,
    const uint16_t *foreground,
    const uint16_t *background,
    uint32_t attributes);
void bufferSetCell(
    opentui_native_handle buffer_handle,
    uint32_t x,
    uint32_t y,
    uint32_t character,
    const uint16_t *foreground,
    const uint16_t *background,
    uint32_t attributes);
void bufferSetCellWithAlphaBlending(
    opentui_native_handle buffer_handle,
    uint32_t x,
    uint32_t y,
    uint32_t character,
    const uint16_t *foreground,
    const uint16_t *background,
    uint32_t attributes);
void bufferFillRect(
    opentui_native_handle buffer_handle,
    uint32_t x,
    uint32_t y,
    uint32_t width,
    uint32_t height,
    const uint16_t *background);
void bufferResize(opentui_native_handle buffer_handle, uint32_t width, uint32_t height);
void bufferDrawGrayscaleBuffer(
    opentui_native_handle buffer_handle,
    int32_t pos_x,
    int32_t pos_y,
    const float *intensities,
    uint32_t source_width,
    uint32_t source_height,
    const uint16_t *foreground,
    const uint16_t *background);
void bufferDrawGrayscaleBufferSupersampled(
    opentui_native_handle buffer_handle,
    int32_t pos_x,
    int32_t pos_y,
    const float *intensities,
    uint32_t source_width,
    uint32_t source_height,
    const uint16_t *foreground,
    const uint16_t *background);
typedef struct opentui_external_grid_draw_options {
  bool draw_inner;
  bool draw_outer;
} opentui_external_grid_draw_options;

/* These layouts mirror the public extern structs in the pinned Zig library.
 * Image values are owned by the native image subsystem; callers only borrow
 * their pixels for the duration of a synchronous operation. */
typedef struct opentui_external_image_info {
  uint32_t width;
  uint32_t height;
  uint32_t source_width;
  uint32_t source_height;
  uint32_t format;
  uint32_t color_status;
  uint32_t orientation;
  uint32_t has_alpha;
} opentui_external_image_info;

typedef struct opentui_external_image_draw_options {
  int32_t x;
  int32_t y;
  uint32_t width;
  uint32_t height;
  uint32_t pixel_width;
  uint32_t pixel_height;
  uint32_t source_x;
  uint32_t source_y;
  uint32_t source_width;
  uint32_t source_height;
  uint32_t protocol;
} opentui_external_image_draw_options;

void bufferDrawGrid(
    opentui_native_handle buffer_handle,
    const uint32_t *border_chars,
    const uint16_t *border_foreground,
    const uint16_t *border_background,
    const int32_t *column_offsets,
    uint32_t column_count,
    const int32_t *row_offsets,
    uint32_t row_count,
    const opentui_external_grid_draw_options *options);
void bufferDrawBox(
    opentui_native_handle buffer_handle,
    int32_t x,
    int32_t y,
    uint32_t width,
    uint32_t height,
    const uint32_t *border_chars,
    uint32_t packed_options,
    const uint16_t *border_color,
    const uint16_t *background_color,
    const uint16_t *title_color,
    const uint8_t *title,
    uint32_t title_length,
    const uint8_t *bottom_title,
    uint32_t bottom_title_length);
void bufferDrawTextBufferView(
    opentui_native_handle buffer_handle,
    opentui_native_handle text_buffer_view_handle,
    int32_t x,
    int32_t y);
uint8_t bufferDrawImage(
    opentui_native_handle buffer_handle,
    opentui_native_handle image_handle,
    const opentui_external_image_draw_options *options);
void bufferColorMatrix(
    opentui_native_handle buffer_handle,
    const float *matrix,
    const float *cell_mask,
    uint32_t cell_mask_count,
    float strength,
    uint8_t target);
void bufferColorMatrixUniform(
    opentui_native_handle buffer_handle,
    const float *matrix,
    float strength,
    uint8_t target);
void bufferPushScissorRect(
    opentui_native_handle buffer_handle,
    int32_t x,
    int32_t y,
    uint32_t width,
    uint32_t height);
void bufferPopScissorRect(opentui_native_handle buffer_handle);
void bufferClearScissorRects(opentui_native_handle buffer_handle);
void bufferPushOpacity(opentui_native_handle buffer_handle, float opacity);
void bufferPopOpacity(opentui_native_handle buffer_handle);
float bufferGetCurrentOpacity(opentui_native_handle buffer_handle);
void bufferClearOpacity(opentui_native_handle buffer_handle);
uint32_t *bufferGetCharPtr(opentui_native_handle buffer_handle);
uint16_t *bufferGetFgPtr(opentui_native_handle buffer_handle);
uint16_t *bufferGetBgPtr(opentui_native_handle buffer_handle);
uint32_t *bufferGetAttributesPtr(opentui_native_handle buffer_handle);

uint32_t imageInfo(
    const uint8_t *data_ptr,
    uint32_t data_len,
    opentui_external_image_info *out_info);
uint32_t imageDecode(
    const uint8_t *data_ptr,
    uint32_t data_len,
    opentui_native_handle *out_handle);
uint32_t imageCreateFromRgba(
    const uint8_t *pixels_ptr,
    uint64_t pixels_len,
    uint32_t width,
    uint32_t height,
    uint32_t stride,
    opentui_native_handle *out_handle);
void imageDestroy(opentui_native_handle image_handle);
uint32_t imageRetain(opentui_native_handle image_handle, opentui_native_handle *out_handle);
uint32_t imageGetInfo(opentui_native_handle image_handle, opentui_external_image_info *out_info);
uint8_t *imageGetPixelsPtr(opentui_native_handle image_handle);
uint32_t imageMaterialize(opentui_native_handle image_handle);
uint32_t imageEnsureEncodedPng(opentui_native_handle image_handle);
uint32_t imageClone(opentui_native_handle image_handle, opentui_native_handle *out_handle);
uint32_t imageCopyPixels(
    opentui_native_handle image_handle,
    uint8_t *destination_ptr,
    uint64_t destination_len,
    uint32_t stride,
    uint8_t bgra);
uint32_t imageResize(
    opentui_native_handle image_handle,
    uint32_t width,
    uint32_t height,
    uint32_t filter,
    opentui_native_handle *out_handle);
uint32_t imageExtract(
    opentui_native_handle image_handle,
    uint32_t left,
    uint32_t top,
    uint32_t width,
    uint32_t height,
    opentui_native_handle *out_handle);
uint32_t imageExtend(
    opentui_native_handle image_handle,
    uint32_t top,
    uint32_t right,
    uint32_t bottom,
    uint32_t left,
    const uint8_t *background_ptr,
    opentui_native_handle *out_handle);
uint32_t imageTransform(
    opentui_native_handle image_handle,
    uint32_t operation,
    opentui_native_handle *out_handle);
uint32_t imageComposite(
    opentui_native_handle base_handle,
    opentui_native_handle overlay_handle,
    int32_t left,
    int32_t top,
    uint32_t blend,
    uint8_t opacity,
    opentui_native_handle *out_handle);

void getRenderStats(
    opentui_native_handle renderer_handle,
    opentui_external_render_stats *output);
void getAllocatorStats(opentui_external_allocator_stats *output);

opentui_yoga_config_ref yogaConfigCreate(void);
void yogaConfigFree(opentui_yoga_config_ref config);
opentui_yoga_node_ref yogaNodeCreateForOpenTUI(void);
void yogaNodeFree(opentui_yoga_node_ref node);
void yogaNodeFreeRecursive(opentui_yoga_node_ref node);
void yogaNodeInsertChild(opentui_yoga_node_ref node, opentui_yoga_node_ref child, uint32_t index);
void yogaNodeRemoveChild(opentui_yoga_node_ref node, opentui_yoga_node_ref child);
uint32_t yogaNodeGetChildCount(opentui_yoga_node_const_ref node);
void yogaNodeCalculateLayout(opentui_yoga_node_ref node, float width, float height, uint32_t direction);
bool yogaNodeIsDirty(opentui_yoga_node_const_ref node);
void yogaNodeMarkDirty(opentui_yoga_node_ref node);
bool yogaNodeGetHasNewLayout(opentui_yoga_node_const_ref node);
void yogaNodeSetHasNewLayout(opentui_yoga_node_ref node, bool has_new_layout);
void yogaNodeGetComputedLayout(
    opentui_yoga_node_const_ref node,
    opentui_external_yoga_layout *output);
void yogaNodeStyleSetValue(
    opentui_yoga_node_ref node,
    uint32_t kind,
    uint32_t edge_or_gutter,
    uint32_t unit,
    float value);
void yogaNodeStyleSetEnum(opentui_yoga_node_ref node, uint32_t kind, uint32_t value);
void yogaNodeStyleSetFloat(opentui_yoga_node_ref node, uint32_t kind, float value);
void yogaNodeStyleSetBorder(opentui_yoga_node_ref node, uint32_t edge, float border);
void yogaNodeSetMeasureFunc(opentui_yoga_node_ref node, bool enabled);
void yogaNodeUnsetMeasureFunc(opentui_yoga_node_ref node);
bool yogaNodeHasMeasureFunc(opentui_yoga_node_const_ref node);
void yogaSetMeasureCallback(const void *callback);
void yogaStoreMeasureResult(float width, float height);

opentui_native_handle createNativeRenderable(void);
void destroyNativeRenderable(opentui_native_handle native_renderable_handle);
bool nativeRenderableAttachYogaNode(
    opentui_native_handle native_renderable_handle,
    opentui_yoga_node_ref node);
bool nativeRenderableSetMeasureTarget(
    opentui_native_handle native_renderable_handle,
    uint32_t kind,
    opentui_native_handle target_handle);

opentui_native_handle createTextBuffer(uint8_t width_method);
void destroyTextBuffer(opentui_native_handle text_buffer_handle);
uint32_t textBufferGetLength(opentui_native_handle text_buffer_handle);
uint32_t textBufferGetByteSize(opentui_native_handle text_buffer_handle);
uint32_t textBufferGetLineCount(opentui_native_handle text_buffer_handle);
uint8_t textBufferGetTabWidth(opentui_native_handle text_buffer_handle);
void textBufferReset(opentui_native_handle text_buffer_handle);
void textBufferClear(opentui_native_handle text_buffer_handle);
bool textBufferLoadFile(
    opentui_native_handle text_buffer_handle,
    const uint8_t *path_ptr,
    uint32_t path_len);
void textBufferSetTabWidth(
    opentui_native_handle text_buffer_handle,
    uint8_t width);
void textBufferSetDefaultFg(
    opentui_native_handle text_buffer_handle,
    const uint16_t *fg);
void textBufferSetDefaultBg(
    opentui_native_handle text_buffer_handle,
    const uint16_t *bg);
void textBufferSetDefaultAttributes(
    opentui_native_handle text_buffer_handle,
    const uint32_t *attributes);
void textBufferResetDefaults(opentui_native_handle text_buffer_handle);
void textBufferSetStyledText(
    opentui_native_handle text_buffer_handle,
    const opentui_external_styled_chunk *chunks,
    uint32_t chunk_count);
void textBufferClearAllHighlights(opentui_native_handle text_buffer_handle);
void textBufferAddHighlightByCharRange(
    opentui_native_handle text_buffer_handle,
    const opentui_external_highlight *highlight);
void textBufferAddHighlight(
    opentui_native_handle text_buffer_handle,
    uint32_t line_index,
    const opentui_external_highlight *highlight);
void textBufferRemoveHighlightsByRef(
    opentui_native_handle text_buffer_handle,
    uint16_t highlight_ref);
void textBufferClearLineHighlights(
    opentui_native_handle text_buffer_handle,
    uint32_t line_index);
bool textBufferSetSyntaxStyle(
    opentui_native_handle text_buffer_handle,
    opentui_native_handle style_handle);
void textBufferAppend(
    opentui_native_handle text_buffer_handle,
    const uint8_t *data_ptr,
    uint32_t data_len);
uint16_t textBufferRegisterMemBuffer(
    opentui_native_handle text_buffer_handle,
    const uint8_t *data_ptr,
    uint32_t data_len,
    bool owned);
bool textBufferReplaceMemBuffer(
    opentui_native_handle text_buffer_handle,
    uint8_t mem_id,
    const uint8_t *data_ptr,
    uint32_t data_len,
    bool owned);
void textBufferSetTextFromMem(
    opentui_native_handle text_buffer_handle,
    uint8_t mem_id);
opentui_native_handle createTextBufferView(
    opentui_native_handle text_buffer_handle);
void destroyTextBufferView(opentui_native_handle text_buffer_view_handle);
void textBufferViewSetWrapWidth(
    opentui_native_handle text_buffer_view_handle,
    uint32_t width);
void textBufferViewSetWrapMode(
    opentui_native_handle text_buffer_view_handle,
    uint8_t mode);
void textBufferViewSetFirstLineOffset(
    opentui_native_handle text_buffer_view_handle,
    uint32_t offset);
void textBufferViewSetSelection(
    opentui_native_handle text_buffer_view_handle,
    uint32_t start,
    uint32_t end,
    const uint16_t *background,
    const uint16_t *foreground);
void textBufferViewUpdateSelection(
    opentui_native_handle text_buffer_view_handle,
    uint32_t end,
    const uint16_t *background,
    const uint16_t *foreground);
void textBufferViewResetSelection(opentui_native_handle text_buffer_view_handle);
uint64_t textBufferViewGetSelectionInfo(opentui_native_handle text_buffer_view_handle);
bool textBufferViewSetLocalSelection(
    opentui_native_handle text_buffer_view_handle,
    int32_t anchor_x,
    int32_t anchor_y,
    int32_t focus_x,
    int32_t focus_y,
    const uint16_t *background,
    const uint16_t *foreground);
bool textBufferViewUpdateLocalSelection(
    opentui_native_handle text_buffer_view_handle,
    int32_t anchor_x,
    int32_t anchor_y,
    int32_t focus_x,
    int32_t focus_y,
    const uint16_t *background,
    const uint16_t *foreground);
void textBufferViewResetLocalSelection(opentui_native_handle text_buffer_view_handle);
uint32_t textBufferViewGetSelectedText(
    opentui_native_handle text_buffer_view_handle,
    uint8_t *output,
    uint32_t output_len);
void textBufferViewSetViewportSize(
    opentui_native_handle text_buffer_view_handle,
    uint32_t width,
    uint32_t height);
void textBufferViewSetViewport(
    opentui_native_handle text_buffer_view_handle,
    uint32_t x,
    uint32_t y,
    uint32_t width,
    uint32_t height);
uint32_t textBufferViewGetVirtualLineCount(opentui_native_handle text_buffer_view_handle);
void textBufferViewSetTabIndicator(
    opentui_native_handle text_buffer_view_handle,
    uint32_t indicator);
void textBufferViewSetTabIndicatorColor(
    opentui_native_handle text_buffer_view_handle,
    const uint16_t *color);
void textBufferViewSetTruncate(
    opentui_native_handle text_buffer_view_handle,
    bool truncate);
bool textBufferViewMeasureForDimensions(
    opentui_native_handle text_buffer_view_handle,
    uint32_t width,
    uint32_t height,
    opentui_external_measure_result *output);
void textBufferViewGetLineInfoDirect(
    opentui_native_handle text_buffer_view_handle,
    opentui_external_line_info *output);
void textBufferViewGetLogicalLineInfoDirect(
    opentui_native_handle text_buffer_view_handle,
    opentui_external_line_info *output);

opentui_native_handle createSyntaxStyle(void);
void destroySyntaxStyle(opentui_native_handle style_handle);
uint32_t syntaxStyleRegister(
    opentui_native_handle style_handle,
    const uint8_t *name_ptr,
    uint32_t name_len,
    const uint16_t *fg,
    const uint16_t *bg,
    uint32_t attributes);
uint32_t syntaxStyleResolveByName(
    opentui_native_handle style_handle,
    const uint8_t *name_ptr,
    uint32_t name_len);
uint32_t syntaxStyleGetStyleCount(opentui_native_handle style_handle);
uint32_t linkAlloc(const uint8_t *url_ptr, uint32_t url_len);
uint32_t linkGetUrl(uint32_t link_id, uint8_t *output, uint32_t output_len);
uint32_t attributesWithLink(uint32_t attributes, uint32_t link_id);
uint32_t attributesGetLinkId(uint32_t attributes);

void getTerminalCapabilities(
    opentui_native_handle renderer_handle,
    opentui_external_capabilities *output);
void processCapabilityResponse(
    opentui_native_handle renderer_handle,
    const uint8_t *response_ptr,
    uint32_t response_len);

opentui_span_feed_ref createNativeSpanFeed(
    const opentui_external_span_feed_options *options);
int32_t attachNativeSpanFeed(opentui_span_feed_ref stream);
int32_t streamClose(opentui_span_feed_ref stream);
void destroyNativeSpanFeed(opentui_span_feed_ref stream);
int32_t streamWrite(
    opentui_span_feed_ref stream,
    const uint8_t *source,
    uint32_t length);
int32_t streamCommit(opentui_span_feed_ref stream);
int32_t streamReserve(
    opentui_span_feed_ref stream,
    uint32_t minimum_length,
    opentui_external_reserve_info *output);
int32_t streamCommitReserved(opentui_span_feed_ref stream, uint32_t length);
int32_t streamCancelReserved(opentui_span_feed_ref stream);
int32_t streamSetOptions(
    opentui_span_feed_ref stream,
    const opentui_external_span_feed_options *options);
int32_t streamGetStats(
    opentui_span_feed_ref stream,
    opentui_external_span_feed_stats *output);
uint32_t streamDrainSpans(
    opentui_span_feed_ref stream,
    opentui_external_span_info *output,
    uint32_t maximum_spans);
int32_t streamMarkSpanConsumed(
    opentui_span_feed_ref stream,
    const opentui_external_span_info *span);
void streamSetCallback(opentui_span_feed_ref stream, opentui_span_feed_callback callback);

_Static_assert(sizeof(opentui_native_handle) == 4, "OpenTUI handles must be u32");
_Static_assert(sizeof(bool) == 1, "OpenTUI bool must have one-byte C ABI storage");
_Static_assert(sizeof(opentui_external_build_options) == 2, "build options ABI drift");
_Static_assert(sizeof(opentui_external_allocator_stats) == 40, "allocator stats ABI drift");
_Static_assert(sizeof(opentui_external_render_stats) == 56, "render stats ABI drift");
_Static_assert(sizeof(opentui_external_cursor_style_options) == 24, "cursor style options ABI drift");
_Static_assert(offsetof(opentui_external_cursor_style_options, color) == 8, "cursor style options color offset drift");
_Static_assert(offsetof(opentui_external_cursor_style_options, cursor) == 16, "cursor style options cursor offset drift");
_Static_assert(sizeof(opentui_external_cursor_state) == 28, "cursor state ABI drift");
_Static_assert(offsetof(opentui_external_cursor_state, y) == 4, "cursor state y offset drift");
_Static_assert(offsetof(opentui_external_cursor_state, visible) == 8, "cursor state visible offset drift");
_Static_assert(offsetof(opentui_external_cursor_state, style) == 9, "cursor state style offset drift");
_Static_assert(offsetof(opentui_external_cursor_state, blinking) == 10, "cursor state blinking offset drift");
_Static_assert(offsetof(opentui_external_cursor_state, r) == 12, "cursor state red offset drift");
_Static_assert(offsetof(opentui_external_cursor_state, g) == 16, "cursor state green offset drift");
_Static_assert(offsetof(opentui_external_cursor_state, b) == 20, "cursor state blue offset drift");
_Static_assert(offsetof(opentui_external_cursor_state, a) == 24, "cursor state alpha offset drift");
_Static_assert(sizeof(opentui_external_yoga_layout) == 24, "Yoga layout ABI drift");
_Static_assert(sizeof(opentui_external_measure_result) == 8, "measure result ABI drift");
_Static_assert(sizeof(opentui_external_styled_chunk) == 56, "styled chunk ABI drift");
_Static_assert(offsetof(opentui_external_styled_chunk, text_len) == 8, "styled chunk text length offset drift");
_Static_assert(offsetof(opentui_external_styled_chunk, fg_ptr) == 16, "styled chunk foreground offset drift");
_Static_assert(offsetof(opentui_external_styled_chunk, bg_ptr) == 24, "styled chunk background offset drift");
_Static_assert(offsetof(opentui_external_styled_chunk, attributes) == 32, "styled chunk attributes offset drift");
_Static_assert(offsetof(opentui_external_styled_chunk, link_ptr) == 40, "styled chunk link offset drift");
_Static_assert(sizeof(opentui_external_grid_draw_options) == 2, "grid draw options ABI drift");
_Static_assert(sizeof(opentui_external_image_info) == 32, "image info ABI drift");
_Static_assert(sizeof(opentui_external_image_draw_options) == 44, "image draw options ABI drift");
_Static_assert(offsetof(opentui_external_image_draw_options, y) == 4, "image draw y offset drift");
_Static_assert(offsetof(opentui_external_image_draw_options, width) == 8, "image draw width offset drift");
_Static_assert(offsetof(opentui_external_image_draw_options, pixel_width) == 16, "image draw pixel width offset drift");
_Static_assert(offsetof(opentui_external_image_draw_options, source_x) == 24, "image draw source x offset drift");
_Static_assert(offsetof(opentui_external_image_draw_options, source_width) == 32, "image draw source width offset drift");
_Static_assert(offsetof(opentui_external_image_draw_options, protocol) == 40, "image draw protocol offset drift");
_Static_assert(offsetof(opentui_external_measure_result, width_cols_max) == 4, "measure result offset drift");
_Static_assert(offsetof(opentui_external_yoga_layout, top) == 4, "Yoga layout offset drift");
_Static_assert(offsetof(opentui_external_yoga_layout, right) == 8, "Yoga layout offset drift");
_Static_assert(offsetof(opentui_external_yoga_layout, bottom) == 12, "Yoga layout offset drift");
_Static_assert(offsetof(opentui_external_yoga_layout, width) == 16, "Yoga layout offset drift");
_Static_assert(offsetof(opentui_external_yoga_layout, height) == 20, "Yoga layout offset drift");
_Static_assert(sizeof(opentui_external_capabilities) == 64, "capabilities ABI drift");
_Static_assert(offsetof(opentui_external_capabilities, term_name_ptr) == 24, "capabilities offset drift");
_Static_assert(offsetof(opentui_external_capabilities, term_name_len) == 32, "capabilities offset drift");
_Static_assert(offsetof(opentui_external_capabilities, term_version_ptr) == 40, "capabilities offset drift");
_Static_assert(offsetof(opentui_external_capabilities, term_version_len) == 48, "capabilities offset drift");
_Static_assert(offsetof(opentui_external_capabilities, term_from_xtversion) == 56, "capabilities offset drift");
_Static_assert(offsetof(opentui_external_capabilities, osc52_support) == 57, "capabilities offset drift");
_Static_assert(offsetof(opentui_external_allocator_stats, active_allocations) == 8, "allocator stats offset drift");
_Static_assert(offsetof(opentui_external_allocator_stats, small_allocations) == 16, "allocator stats offset drift");
_Static_assert(offsetof(opentui_external_allocator_stats, large_allocations) == 24, "allocator stats offset drift");
_Static_assert(offsetof(opentui_external_allocator_stats, requested_bytes_valid) == 32, "allocator stats offset drift");
_Static_assert(offsetof(opentui_external_render_stats, average_frame_time) == 8, "render stats offset drift");
_Static_assert(offsetof(opentui_external_render_stats, render_time) == 16, "render stats offset drift");
_Static_assert(offsetof(opentui_external_render_stats, stdout_write_time) == 24, "render stats offset drift");
_Static_assert(offsetof(opentui_external_render_stats, frame_count) == 32, "render stats offset drift");
_Static_assert(offsetof(opentui_external_render_stats, cells_updated) == 40, "render stats offset drift");
_Static_assert(offsetof(opentui_external_render_stats, average_cells_updated) == 44, "render stats offset drift");
_Static_assert(offsetof(opentui_external_render_stats, render_time_valid) == 48, "render stats offset drift");
_Static_assert(offsetof(opentui_external_render_stats, stdout_write_time_valid) == 49, "render stats offset drift");
_Static_assert(sizeof(uintptr_t) == sizeof(void *), "uintptr_t ABI drift");
_Static_assert(sizeof(opentui_external_span_feed_options) == 24, "span feed options ABI drift");
_Static_assert(offsetof(opentui_external_span_feed_options, initial_chunks) == 4, "span feed options offset drift");
_Static_assert(offsetof(opentui_external_span_feed_options, max_bytes) == 8, "span feed options offset drift");
_Static_assert(offsetof(opentui_external_span_feed_options, growth_policy) == 16, "span feed options offset drift");
_Static_assert(offsetof(opentui_external_span_feed_options, auto_commit_on_full) == 17, "span feed options offset drift");
_Static_assert(offsetof(opentui_external_span_feed_options, span_queue_capacity) == 20, "span feed options offset drift");
_Static_assert(sizeof(opentui_external_span_feed_stats) == 24, "span feed stats ABI drift");
_Static_assert(offsetof(opentui_external_span_feed_stats, spans_committed) == 8, "span feed stats offset drift");
_Static_assert(offsetof(opentui_external_span_feed_stats, chunks) == 16, "span feed stats offset drift");
_Static_assert(offsetof(opentui_external_span_feed_stats, pending_spans) == 20, "span feed stats offset drift");
_Static_assert(sizeof(opentui_external_span_info) == 24, "span info ABI drift");
_Static_assert(offsetof(opentui_external_span_info, offset) == 8, "span info offset drift");
_Static_assert(offsetof(opentui_external_span_info, len) == 12, "span info offset drift");
_Static_assert(offsetof(opentui_external_span_info, chunk_index) == 16, "span info offset drift");
_Static_assert(offsetof(opentui_external_span_info, reserved) == 20, "span info offset drift");
_Static_assert(sizeof(opentui_external_reserve_info) == 16, "reserve info ABI drift");
_Static_assert(offsetof(opentui_external_reserve_info, len) == 8, "reserve info offset drift");
_Static_assert(offsetof(opentui_external_reserve_info, reserved) == 12, "reserve info offset drift");

typedef opentui_native_handle (*opentui_create_event_sink_fn)(opentui_event_callback);
typedef void (*opentui_destroy_event_sink_fn)(opentui_native_handle);
typedef opentui_native_handle (*opentui_create_edit_buffer_fn)(uint8_t, opentui_native_handle);
typedef void (*opentui_destroy_edit_buffer_fn)(opentui_native_handle);
typedef void (*opentui_edit_buffer_insert_text_fn)(opentui_native_handle, const uint8_t *, uint32_t);
typedef opentui_native_handle (*opentui_create_renderer_fn)(uint32_t, uint32_t, uint8_t, uint8_t, void *);
typedef void (*opentui_set_use_thread_fn)(opentui_native_handle, bool);
typedef void (*opentui_resize_renderer_fn)(opentui_native_handle, uint32_t, uint32_t);
typedef void (*opentui_set_background_color_fn)(opentui_native_handle, const uint16_t *);
typedef void (*opentui_set_cursor_position_fn)(opentui_native_handle, int32_t, int32_t, bool);
typedef void (*opentui_set_cursor_color_fn)(opentui_native_handle, const uint16_t *);
typedef void (*opentui_set_cursor_style_options_fn)(opentui_native_handle, const opentui_external_cursor_style_options *);
typedef void (*opentui_get_cursor_state_fn)(opentui_native_handle, opentui_external_cursor_state *);
typedef void (*opentui_destroy_renderer_fn)(opentui_native_handle);
typedef opentui_native_handle (*opentui_get_buffer_fn)(opentui_native_handle);
typedef uint8_t (*opentui_render_fn)(opentui_native_handle, bool);
typedef void (*opentui_hit_grid_rect_fn)(opentui_native_handle, int32_t, int32_t, uint32_t, uint32_t, uint32_t);
typedef void (*opentui_hit_grid_scissor_fn)(opentui_native_handle, int32_t, int32_t, uint32_t, uint32_t);
typedef void (*opentui_hit_grid_clear_fn)(opentui_native_handle);
typedef uint32_t (*opentui_check_hit_fn)(opentui_native_handle, uint32_t, uint32_t);
typedef bool (*opentui_get_hit_grid_dirty_fn)(opentui_native_handle);
typedef uint32_t (*opentui_get_buffer_dimension_fn)(opentui_native_handle);
typedef opentui_native_handle (*opentui_create_optimized_buffer_fn)(uint32_t, uint32_t, bool, uint8_t, const uint8_t *, uint32_t);
typedef void (*opentui_destroy_optimized_buffer_fn)(opentui_native_handle);
typedef void (*opentui_draw_frame_buffer_fn)(opentui_native_handle, int32_t, int32_t, opentui_native_handle, uint32_t, uint32_t, uint32_t, uint32_t);
typedef void (*opentui_buffer_clear_fn)(opentui_native_handle, const uint16_t *);
typedef uint32_t (*opentui_buffer_write_fn)(opentui_native_handle, uint8_t *, uint32_t, bool);
typedef void (*opentui_buffer_draw_text_fn)(opentui_native_handle, const uint8_t *, uint32_t, uint32_t, uint32_t, const uint16_t *, const uint16_t *, uint32_t);
typedef void (*opentui_buffer_draw_box_fn)(opentui_native_handle, int32_t, int32_t, uint32_t, uint32_t, const uint32_t *, uint32_t, const uint16_t *, const uint16_t *, const uint16_t *, const uint8_t *, uint32_t, const uint8_t *, uint32_t);
typedef void (*opentui_buffer_set_cell_fn)(opentui_native_handle, uint32_t, uint32_t, uint32_t, const uint16_t *, const uint16_t *, uint32_t);
typedef void (*opentui_buffer_set_cell_with_alpha_blending_fn)(opentui_native_handle, uint32_t, uint32_t, uint32_t, const uint16_t *, const uint16_t *, uint32_t);
typedef void (*opentui_buffer_fill_rect_fn)(opentui_native_handle, uint32_t, uint32_t, uint32_t, uint32_t, const uint16_t *);
typedef void (*opentui_buffer_resize_fn)(opentui_native_handle, uint32_t, uint32_t);
typedef void (*opentui_buffer_draw_grayscale_buffer_fn)(opentui_native_handle, int32_t, int32_t, const float *, uint32_t, uint32_t, const uint16_t *, const uint16_t *);
typedef void (*opentui_buffer_draw_grayscale_buffer_supersampled_fn)(opentui_native_handle, int32_t, int32_t, const float *, uint32_t, uint32_t, const uint16_t *, const uint16_t *);
typedef void (*opentui_buffer_draw_grid_fn)(opentui_native_handle, const uint32_t *, const uint16_t *, const uint16_t *, const int32_t *, uint32_t, const int32_t *, uint32_t, const opentui_external_grid_draw_options *);
typedef void (*opentui_buffer_draw_text_buffer_view_fn)(opentui_native_handle, opentui_native_handle, int32_t, int32_t);
typedef uint8_t (*opentui_buffer_draw_image_fn)(opentui_native_handle, opentui_native_handle, const opentui_external_image_draw_options *);
typedef void (*opentui_buffer_color_matrix_fn)(opentui_native_handle, const float *, const float *, uint32_t, float, uint8_t);
typedef void (*opentui_buffer_color_matrix_uniform_fn)(opentui_native_handle, const float *, float, uint8_t);
typedef void (*opentui_buffer_push_scissor_rect_fn)(opentui_native_handle, int32_t, int32_t, uint32_t, uint32_t);
typedef void (*opentui_buffer_pop_scissor_rect_fn)(opentui_native_handle);
typedef void (*opentui_buffer_clear_scissor_rects_fn)(opentui_native_handle);
typedef void (*opentui_buffer_push_opacity_fn)(opentui_native_handle, float);
typedef void (*opentui_buffer_pop_opacity_fn)(opentui_native_handle);
typedef float (*opentui_buffer_get_current_opacity_fn)(opentui_native_handle);
typedef void (*opentui_buffer_clear_opacity_fn)(opentui_native_handle);
typedef uint32_t (*opentui_image_info_fn)(const uint8_t *, uint32_t, opentui_external_image_info *);
typedef uint32_t (*opentui_image_decode_fn)(const uint8_t *, uint32_t, opentui_native_handle *);
typedef uint32_t (*opentui_image_create_from_rgba_fn)(const uint8_t *, uint64_t, uint32_t, uint32_t, uint32_t, opentui_native_handle *);
typedef void (*opentui_image_destroy_fn)(opentui_native_handle);
typedef uint32_t (*opentui_image_retain_fn)(opentui_native_handle, opentui_native_handle *);
typedef uint32_t (*opentui_image_get_info_fn)(opentui_native_handle, opentui_external_image_info *);
typedef uint8_t *(*opentui_image_get_pixels_ptr_fn)(opentui_native_handle);
typedef uint32_t (*opentui_image_materialize_fn)(opentui_native_handle);
typedef uint32_t (*opentui_image_ensure_encoded_png_fn)(opentui_native_handle);
typedef uint32_t (*opentui_image_clone_fn)(opentui_native_handle, opentui_native_handle *);
typedef uint32_t (*opentui_image_copy_pixels_fn)(opentui_native_handle, uint8_t *, uint64_t, uint32_t, uint8_t);
typedef uint32_t (*opentui_image_resize_fn)(opentui_native_handle, uint32_t, uint32_t, uint32_t, opentui_native_handle *);
typedef uint32_t (*opentui_image_extract_fn)(opentui_native_handle, uint32_t, uint32_t, uint32_t, uint32_t, opentui_native_handle *);
typedef uint32_t (*opentui_image_extend_fn)(opentui_native_handle, uint32_t, uint32_t, uint32_t, uint32_t, const uint8_t *, opentui_native_handle *);
typedef uint32_t (*opentui_image_transform_fn)(opentui_native_handle, uint32_t, opentui_native_handle *);
typedef uint32_t (*opentui_image_composite_fn)(opentui_native_handle, opentui_native_handle, int32_t, int32_t, uint32_t, uint8_t, opentui_native_handle *);
typedef void (*opentui_get_render_stats_fn)(opentui_native_handle, opentui_external_render_stats *);
typedef void (*opentui_get_allocator_stats_fn)(opentui_external_allocator_stats *);
typedef opentui_yoga_config_ref (*opentui_yoga_config_create_fn)(void);
typedef void (*opentui_yoga_config_free_fn)(opentui_yoga_config_ref);
typedef opentui_yoga_node_ref (*opentui_yoga_node_create_for_opentui_fn)(void);
typedef void (*opentui_yoga_node_free_fn)(opentui_yoga_node_ref);
typedef void (*opentui_yoga_node_free_recursive_fn)(opentui_yoga_node_ref);
typedef void (*opentui_yoga_node_insert_child_fn)(opentui_yoga_node_ref, opentui_yoga_node_ref, uint32_t);
typedef void (*opentui_yoga_node_remove_child_fn)(opentui_yoga_node_ref, opentui_yoga_node_ref);
typedef uint32_t (*opentui_yoga_node_get_child_count_fn)(opentui_yoga_node_const_ref);
typedef void (*opentui_yoga_node_calculate_layout_fn)(opentui_yoga_node_ref, float, float, uint32_t);
typedef bool (*opentui_yoga_node_is_dirty_fn)(opentui_yoga_node_const_ref);
typedef void (*opentui_yoga_node_mark_dirty_fn)(opentui_yoga_node_ref);
typedef bool (*opentui_yoga_node_get_has_new_layout_fn)(opentui_yoga_node_const_ref);
typedef void (*opentui_yoga_node_set_has_new_layout_fn)(opentui_yoga_node_ref, bool);
typedef void (*opentui_yoga_node_get_computed_layout_fn)(opentui_yoga_node_const_ref, opentui_external_yoga_layout *);
typedef void (*opentui_yoga_node_style_set_value_fn)(opentui_yoga_node_ref, uint32_t, uint32_t, uint32_t, float);
typedef void (*opentui_yoga_node_style_set_enum_fn)(opentui_yoga_node_ref, uint32_t, uint32_t);
typedef void (*opentui_yoga_node_style_set_float_fn)(opentui_yoga_node_ref, uint32_t, float);
typedef void (*opentui_yoga_node_style_set_border_fn)(opentui_yoga_node_ref, uint32_t, float);
typedef void (*opentui_yoga_node_set_measure_func_fn)(opentui_yoga_node_ref, bool);
typedef void (*opentui_yoga_node_unset_measure_func_fn)(opentui_yoga_node_ref);
typedef bool (*opentui_yoga_node_has_measure_func_fn)(opentui_yoga_node_const_ref);
typedef void (*opentui_yoga_set_measure_callback_fn)(const void *);
typedef void (*opentui_yoga_store_measure_result_fn)(float, float);
typedef opentui_native_handle (*opentui_create_native_renderable_fn)(void);
typedef void (*opentui_destroy_native_renderable_fn)(opentui_native_handle);
typedef bool (*opentui_native_renderable_attach_yoga_node_fn)(opentui_native_handle, opentui_yoga_node_ref);
typedef bool (*opentui_native_renderable_set_measure_target_fn)(opentui_native_handle, uint32_t, opentui_native_handle);
typedef opentui_native_handle (*opentui_create_text_buffer_fn)(uint8_t);
typedef void (*opentui_destroy_text_buffer_fn)(opentui_native_handle);
typedef uint32_t (*opentui_text_buffer_get_length_fn)(opentui_native_handle);
typedef uint32_t (*opentui_text_buffer_get_byte_size_fn)(opentui_native_handle);
typedef uint32_t (*opentui_text_buffer_get_line_count_fn)(opentui_native_handle);
typedef uint8_t (*opentui_text_buffer_get_tab_width_fn)(opentui_native_handle);
typedef void (*opentui_text_buffer_reset_fn)(opentui_native_handle);
typedef void (*opentui_text_buffer_clear_fn)(opentui_native_handle);
typedef bool (*opentui_text_buffer_load_file_fn)(
    opentui_native_handle,
    const uint8_t *,
    uint32_t);
typedef void (*opentui_text_buffer_set_tab_width_fn)(
    opentui_native_handle,
    uint8_t);
typedef void (*opentui_text_buffer_append_fn)(opentui_native_handle, const uint8_t *, uint32_t);
typedef uint16_t (*opentui_text_buffer_register_mem_buffer_fn)(opentui_native_handle, const uint8_t *, uint32_t, bool);
typedef bool (*opentui_text_buffer_replace_mem_buffer_fn)(opentui_native_handle, uint8_t, const uint8_t *, uint32_t, bool);
typedef void (*opentui_text_buffer_set_text_from_mem_fn)(opentui_native_handle, uint8_t);
typedef void (*opentui_text_buffer_set_default_fg_fn)(opentui_native_handle, const uint16_t *);
typedef void (*opentui_text_buffer_set_default_bg_fn)(opentui_native_handle, const uint16_t *);
typedef void (*opentui_text_buffer_set_default_attributes_fn)(opentui_native_handle, const uint32_t *);
typedef void (*opentui_text_buffer_reset_defaults_fn)(opentui_native_handle);
typedef void (*opentui_text_buffer_set_styled_text_fn)(opentui_native_handle, const opentui_external_styled_chunk *, uint32_t);
typedef void (*opentui_text_buffer_clear_all_highlights_fn)(opentui_native_handle);
typedef void (*opentui_text_buffer_add_highlight_by_char_range_fn)(opentui_native_handle, const opentui_external_highlight *);
typedef void (*opentui_text_buffer_add_highlight_fn)(opentui_native_handle, uint32_t, const opentui_external_highlight *);
typedef void (*opentui_text_buffer_remove_highlights_by_ref_fn)(opentui_native_handle, uint16_t);
typedef void (*opentui_text_buffer_clear_line_highlights_fn)(opentui_native_handle, uint32_t);
typedef bool (*opentui_text_buffer_set_syntax_style_fn)(opentui_native_handle, opentui_native_handle);
typedef opentui_native_handle (*opentui_create_syntax_style_fn)(void);
typedef void (*opentui_destroy_syntax_style_fn)(opentui_native_handle);
typedef uint32_t (*opentui_syntax_style_register_fn)(opentui_native_handle, const uint8_t *, uint32_t, const uint16_t *, const uint16_t *, uint32_t);
typedef uint32_t (*opentui_syntax_style_resolve_fn)(opentui_native_handle, const uint8_t *, uint32_t);
typedef uint32_t (*opentui_syntax_style_count_fn)(opentui_native_handle);
typedef opentui_native_handle (*opentui_create_text_buffer_view_fn)(opentui_native_handle);
typedef void (*opentui_destroy_text_buffer_view_fn)(opentui_native_handle);
typedef void (*opentui_text_buffer_view_set_wrap_width_fn)(opentui_native_handle, uint32_t);
typedef void (*opentui_text_buffer_view_set_wrap_mode_fn)(opentui_native_handle, uint8_t);
typedef void (*opentui_text_buffer_view_set_first_line_offset_fn)(opentui_native_handle, uint32_t);
typedef void (*opentui_text_buffer_view_set_selection_fn)(opentui_native_handle, uint32_t, uint32_t, const uint16_t *, const uint16_t *);
typedef void (*opentui_text_buffer_view_update_selection_fn)(opentui_native_handle, uint32_t, const uint16_t *, const uint16_t *);
typedef void (*opentui_text_buffer_view_reset_selection_fn)(opentui_native_handle);
typedef uint64_t (*opentui_text_buffer_view_get_selection_info_fn)(opentui_native_handle);
typedef bool (*opentui_text_buffer_view_set_local_selection_fn)(opentui_native_handle, int32_t, int32_t, int32_t, int32_t, const uint16_t *, const uint16_t *);
typedef bool (*opentui_text_buffer_view_update_local_selection_fn)(opentui_native_handle, int32_t, int32_t, int32_t, int32_t, const uint16_t *, const uint16_t *);
typedef void (*opentui_text_buffer_view_reset_local_selection_fn)(opentui_native_handle);
typedef uint32_t (*opentui_text_buffer_view_get_selected_text_fn)(opentui_native_handle, uint8_t *, uint32_t);
typedef void (*opentui_text_buffer_view_set_viewport_size_fn)(opentui_native_handle, uint32_t, uint32_t);
typedef void (*opentui_text_buffer_view_set_viewport_fn)(opentui_native_handle, uint32_t, uint32_t, uint32_t, uint32_t);
typedef uint32_t (*opentui_text_buffer_view_get_virtual_line_count_fn)(opentui_native_handle);
typedef void (*opentui_text_buffer_view_set_tab_indicator_fn)(opentui_native_handle, uint32_t);
typedef void (*opentui_text_buffer_view_set_tab_indicator_color_fn)(opentui_native_handle, const uint16_t *);
typedef void (*opentui_text_buffer_view_set_truncate_fn)(opentui_native_handle, bool);
typedef bool (*opentui_text_buffer_view_measure_for_dimensions_fn)(opentui_native_handle, uint32_t, uint32_t, opentui_external_measure_result *);
typedef void (*opentui_text_buffer_view_get_line_info_direct_fn)(opentui_native_handle, opentui_external_line_info *);
typedef void (*opentui_text_buffer_view_get_logical_line_info_direct_fn)(opentui_native_handle, opentui_external_line_info *);
typedef void (*opentui_get_terminal_capabilities_fn)(opentui_native_handle, opentui_external_capabilities *);
typedef void (*opentui_process_capability_response_fn)(opentui_native_handle, const uint8_t *, uint32_t);
typedef opentui_span_feed_ref (*opentui_create_native_span_feed_fn)(const opentui_external_span_feed_options *);
typedef int32_t (*opentui_span_feed_status_fn)(opentui_span_feed_ref);
typedef void (*opentui_destroy_native_span_feed_fn)(opentui_span_feed_ref);
typedef int32_t (*opentui_span_feed_write_fn)(opentui_span_feed_ref, const uint8_t *, uint32_t);
typedef int32_t (*opentui_span_feed_reserve_fn)(opentui_span_feed_ref, uint32_t, opentui_external_reserve_info *);
typedef int32_t (*opentui_span_feed_commit_reserved_fn)(opentui_span_feed_ref, uint32_t);
typedef int32_t (*opentui_span_feed_options_fn)(opentui_span_feed_ref, const opentui_external_span_feed_options *);
typedef int32_t (*opentui_span_feed_stats_fn)(opentui_span_feed_ref, opentui_external_span_feed_stats *);
typedef uint32_t (*opentui_span_feed_drain_fn)(opentui_span_feed_ref, opentui_external_span_info *, uint32_t);
typedef int32_t (*opentui_span_feed_consume_fn)(opentui_span_feed_ref, const opentui_external_span_info *);
typedef void (*opentui_span_feed_callback_fn)(opentui_span_feed_ref, opentui_span_feed_callback);

_Static_assert(_Generic(&createEventSink, opentui_create_event_sink_fn: 1, default: 0), "createEventSink ABI drift");
_Static_assert(_Generic(&destroyEventSink, opentui_destroy_event_sink_fn: 1, default: 0), "destroyEventSink ABI drift");
_Static_assert(_Generic(&createEditBuffer, opentui_create_edit_buffer_fn: 1, default: 0), "createEditBuffer ABI drift");
_Static_assert(_Generic(&destroyEditBuffer, opentui_destroy_edit_buffer_fn: 1, default: 0), "destroyEditBuffer ABI drift");
_Static_assert(_Generic(&editBufferInsertText, opentui_edit_buffer_insert_text_fn: 1, default: 0), "editBufferInsertText ABI drift");
_Static_assert(_Generic(&createRenderer, opentui_create_renderer_fn: 1, default: 0), "createRenderer ABI drift");
_Static_assert(_Generic(&setUseThread, opentui_set_use_thread_fn: 1, default: 0), "setUseThread ABI drift");
_Static_assert(_Generic(&resizeRenderer, opentui_resize_renderer_fn: 1, default: 0), "resizeRenderer ABI drift");
_Static_assert(_Generic(&setBackgroundColor, opentui_set_background_color_fn: 1, default: 0), "setBackgroundColor ABI drift");
_Static_assert(_Generic(&setCursorPosition, opentui_set_cursor_position_fn: 1, default: 0), "setCursorPosition ABI drift");
_Static_assert(_Generic(&setCursorColor, opentui_set_cursor_color_fn: 1, default: 0), "setCursorColor ABI drift");
_Static_assert(_Generic(&setCursorStyleOptions, opentui_set_cursor_style_options_fn: 1, default: 0), "setCursorStyleOptions ABI drift");
_Static_assert(_Generic(&getCursorState, opentui_get_cursor_state_fn: 1, default: 0), "getCursorState ABI drift");
_Static_assert(_Generic(&destroyRenderer, opentui_destroy_renderer_fn: 1, default: 0), "destroyRenderer ABI drift");
_Static_assert(_Generic(&getCurrentBuffer, opentui_get_buffer_fn: 1, default: 0), "getCurrentBuffer ABI drift");
_Static_assert(_Generic(&getNextBuffer, opentui_get_buffer_fn: 1, default: 0), "getNextBuffer ABI drift");
_Static_assert(OPENTUI_RENDER_STATUS_RENDERED == 0, "rendered status ABI drift");
_Static_assert(OPENTUI_RENDER_STATUS_SKIPPED == 1, "skipped status ABI drift");
_Static_assert(OPENTUI_RENDER_STATUS_FAILED == 2, "failed status ABI drift");
_Static_assert(_Generic(&render, opentui_render_fn: 1, default: 0), "render ABI drift");
_Static_assert(_Generic(&addToHitGrid, opentui_hit_grid_rect_fn: 1, default: 0), "addToHitGrid ABI drift");
_Static_assert(_Generic(&clearCurrentHitGrid, opentui_hit_grid_clear_fn: 1, default: 0), "clearCurrentHitGrid ABI drift");
_Static_assert(_Generic(&hitGridPushScissorRect, opentui_hit_grid_scissor_fn: 1, default: 0), "hitGridPushScissorRect ABI drift");
_Static_assert(_Generic(&hitGridPopScissorRect, opentui_hit_grid_clear_fn: 1, default: 0), "hitGridPopScissorRect ABI drift");
_Static_assert(_Generic(&hitGridClearScissorRects, opentui_hit_grid_clear_fn: 1, default: 0), "hitGridClearScissorRects ABI drift");
_Static_assert(_Generic(&addToCurrentHitGridClipped, opentui_hit_grid_rect_fn: 1, default: 0), "addToCurrentHitGridClipped ABI drift");
_Static_assert(_Generic(&checkHit, opentui_check_hit_fn: 1, default: 0), "checkHit ABI drift");
_Static_assert(_Generic(&getHitGridDirty, opentui_get_hit_grid_dirty_fn: 1, default: 0), "getHitGridDirty ABI drift");
_Static_assert(_Generic(&clearNextHitGrid, opentui_hit_grid_clear_fn: 1, default: 0), "clearNextHitGrid ABI drift");
_Static_assert(_Generic(&getBufferWidth, opentui_get_buffer_dimension_fn: 1, default: 0), "getBufferWidth ABI drift");
_Static_assert(_Generic(&getBufferHeight, opentui_get_buffer_dimension_fn: 1, default: 0), "getBufferHeight ABI drift");
_Static_assert(_Generic(&createOptimizedBuffer, opentui_create_optimized_buffer_fn: 1, default: 0), "createOptimizedBuffer ABI drift");
_Static_assert(_Generic(&destroyOptimizedBuffer, opentui_destroy_optimized_buffer_fn: 1, default: 0), "destroyOptimizedBuffer ABI drift");
_Static_assert(_Generic(&destroyFrameBuffer, opentui_destroy_optimized_buffer_fn: 1, default: 0), "destroyFrameBuffer ABI drift");
_Static_assert(_Generic(&drawFrameBuffer, opentui_draw_frame_buffer_fn: 1, default: 0), "drawFrameBuffer ABI drift");
_Static_assert(_Generic(&bufferClear, opentui_buffer_clear_fn: 1, default: 0), "bufferClear ABI drift");
_Static_assert(_Generic(&bufferWriteResolvedChars, opentui_buffer_write_fn: 1, default: 0), "bufferWriteResolvedChars ABI drift");
_Static_assert(_Generic(&bufferDrawText, opentui_buffer_draw_text_fn: 1, default: 0), "bufferDrawText ABI drift");
_Static_assert(_Generic(&bufferDrawBox, opentui_buffer_draw_box_fn: 1, default: 0), "bufferDrawBox ABI drift");
_Static_assert(_Generic(&bufferSetCell, opentui_buffer_set_cell_fn: 1, default: 0), "bufferSetCell ABI drift");
_Static_assert(_Generic(&bufferSetCellWithAlphaBlending, opentui_buffer_set_cell_with_alpha_blending_fn: 1, default: 0), "bufferSetCellWithAlphaBlending ABI drift");
_Static_assert(_Generic(&bufferFillRect, opentui_buffer_fill_rect_fn: 1, default: 0), "bufferFillRect ABI drift");
_Static_assert(_Generic(&bufferResize, opentui_buffer_resize_fn: 1, default: 0), "bufferResize ABI drift");
_Static_assert(_Generic(&bufferDrawGrayscaleBuffer, opentui_buffer_draw_grayscale_buffer_fn: 1, default: 0), "bufferDrawGrayscaleBuffer ABI drift");
_Static_assert(_Generic(&bufferDrawGrayscaleBufferSupersampled, opentui_buffer_draw_grayscale_buffer_supersampled_fn: 1, default: 0), "bufferDrawGrayscaleBufferSupersampled ABI drift");
_Static_assert(_Generic(&bufferDrawGrid, opentui_buffer_draw_grid_fn: 1, default: 0), "bufferDrawGrid ABI drift");
_Static_assert(_Generic(&bufferDrawTextBufferView, opentui_buffer_draw_text_buffer_view_fn: 1, default: 0), "bufferDrawTextBufferView ABI drift");
_Static_assert(_Generic(&bufferDrawImage, opentui_buffer_draw_image_fn: 1, default: 0), "bufferDrawImage ABI drift");
_Static_assert(_Generic(&bufferColorMatrix, opentui_buffer_color_matrix_fn: 1, default: 0), "bufferColorMatrix ABI drift");
_Static_assert(_Generic(&bufferColorMatrixUniform, opentui_buffer_color_matrix_uniform_fn: 1, default: 0), "bufferColorMatrixUniform ABI drift");
_Static_assert(_Generic(&bufferPushScissorRect, opentui_buffer_push_scissor_rect_fn: 1, default: 0), "bufferPushScissorRect ABI drift");
_Static_assert(_Generic(&bufferPopScissorRect, opentui_buffer_pop_scissor_rect_fn: 1, default: 0), "bufferPopScissorRect ABI drift");
_Static_assert(_Generic(&bufferClearScissorRects, opentui_buffer_clear_scissor_rects_fn: 1, default: 0), "bufferClearScissorRects ABI drift");
_Static_assert(_Generic(&bufferPushOpacity, opentui_buffer_push_opacity_fn: 1, default: 0), "bufferPushOpacity ABI drift");
_Static_assert(_Generic(&bufferPopOpacity, opentui_buffer_pop_opacity_fn: 1, default: 0), "bufferPopOpacity ABI drift");
_Static_assert(_Generic(&bufferGetCurrentOpacity, opentui_buffer_get_current_opacity_fn: 1, default: 0), "bufferGetCurrentOpacity ABI drift");
_Static_assert(_Generic(&bufferClearOpacity, opentui_buffer_clear_opacity_fn: 1, default: 0), "bufferClearOpacity ABI drift");
_Static_assert(_Generic(&imageInfo, opentui_image_info_fn: 1, default: 0), "imageInfo ABI drift");
_Static_assert(_Generic(&imageDecode, opentui_image_decode_fn: 1, default: 0), "imageDecode ABI drift");
_Static_assert(_Generic(&imageCreateFromRgba, opentui_image_create_from_rgba_fn: 1, default: 0), "imageCreateFromRgba ABI drift");
_Static_assert(_Generic(&imageDestroy, opentui_image_destroy_fn: 1, default: 0), "imageDestroy ABI drift");
_Static_assert(_Generic(&imageRetain, opentui_image_retain_fn: 1, default: 0), "imageRetain ABI drift");
_Static_assert(_Generic(&imageGetInfo, opentui_image_get_info_fn: 1, default: 0), "imageGetInfo ABI drift");
_Static_assert(_Generic(&imageGetPixelsPtr, opentui_image_get_pixels_ptr_fn: 1, default: 0), "imageGetPixelsPtr ABI drift");
_Static_assert(_Generic(&imageMaterialize, opentui_image_materialize_fn: 1, default: 0), "imageMaterialize ABI drift");
_Static_assert(_Generic(&imageEnsureEncodedPng, opentui_image_ensure_encoded_png_fn: 1, default: 0), "imageEnsureEncodedPng ABI drift");
_Static_assert(_Generic(&imageClone, opentui_image_clone_fn: 1, default: 0), "imageClone ABI drift");
_Static_assert(_Generic(&imageCopyPixels, opentui_image_copy_pixels_fn: 1, default: 0), "imageCopyPixels ABI drift");
_Static_assert(_Generic(&imageResize, opentui_image_resize_fn: 1, default: 0), "imageResize ABI drift");
_Static_assert(_Generic(&imageExtract, opentui_image_extract_fn: 1, default: 0), "imageExtract ABI drift");
_Static_assert(_Generic(&imageExtend, opentui_image_extend_fn: 1, default: 0), "imageExtend ABI drift");
_Static_assert(_Generic(&imageTransform, opentui_image_transform_fn: 1, default: 0), "imageTransform ABI drift");
_Static_assert(_Generic(&imageComposite, opentui_image_composite_fn: 1, default: 0), "imageComposite ABI drift");
_Static_assert(_Generic(&getRenderStats, opentui_get_render_stats_fn: 1, default: 0), "getRenderStats ABI drift");
_Static_assert(_Generic(&getAllocatorStats, opentui_get_allocator_stats_fn: 1, default: 0), "getAllocatorStats ABI drift");
_Static_assert(_Generic(&yogaConfigCreate, opentui_yoga_config_create_fn: 1, default: 0), "yogaConfigCreate ABI drift");
_Static_assert(_Generic(&yogaConfigFree, opentui_yoga_config_free_fn: 1, default: 0), "yogaConfigFree ABI drift");
_Static_assert(_Generic(&yogaNodeCreateForOpenTUI, opentui_yoga_node_create_for_opentui_fn: 1, default: 0), "yogaNodeCreateForOpenTUI ABI drift");
_Static_assert(_Generic(&yogaNodeFree, opentui_yoga_node_free_fn: 1, default: 0), "yogaNodeFree ABI drift");
_Static_assert(_Generic(&yogaNodeFreeRecursive, opentui_yoga_node_free_recursive_fn: 1, default: 0), "yogaNodeFreeRecursive ABI drift");
_Static_assert(_Generic(&yogaNodeInsertChild, opentui_yoga_node_insert_child_fn: 1, default: 0), "yogaNodeInsertChild ABI drift");
_Static_assert(_Generic(&yogaNodeRemoveChild, opentui_yoga_node_remove_child_fn: 1, default: 0), "yogaNodeRemoveChild ABI drift");
_Static_assert(_Generic(&yogaNodeGetChildCount, opentui_yoga_node_get_child_count_fn: 1, default: 0), "yogaNodeGetChildCount ABI drift");
_Static_assert(_Generic(&yogaNodeCalculateLayout, opentui_yoga_node_calculate_layout_fn: 1, default: 0), "yogaNodeCalculateLayout ABI drift");
_Static_assert(_Generic(&yogaNodeIsDirty, opentui_yoga_node_is_dirty_fn: 1, default: 0), "yogaNodeIsDirty ABI drift");
_Static_assert(_Generic(&yogaNodeMarkDirty, opentui_yoga_node_mark_dirty_fn: 1, default: 0), "yogaNodeMarkDirty ABI drift");
_Static_assert(_Generic(&yogaNodeGetHasNewLayout, opentui_yoga_node_get_has_new_layout_fn: 1, default: 0), "yogaNodeGetHasNewLayout ABI drift");
_Static_assert(_Generic(&yogaNodeSetHasNewLayout, opentui_yoga_node_set_has_new_layout_fn: 1, default: 0), "yogaNodeSetHasNewLayout ABI drift");
_Static_assert(_Generic(&yogaNodeGetComputedLayout, opentui_yoga_node_get_computed_layout_fn: 1, default: 0), "yogaNodeGetComputedLayout ABI drift");
_Static_assert(_Generic(&yogaNodeStyleSetValue, opentui_yoga_node_style_set_value_fn: 1, default: 0), "yogaNodeStyleSetValue ABI drift");
_Static_assert(_Generic(&yogaNodeStyleSetEnum, opentui_yoga_node_style_set_enum_fn: 1, default: 0), "yogaNodeStyleSetEnum ABI drift");
_Static_assert(_Generic(&yogaNodeStyleSetFloat, opentui_yoga_node_style_set_float_fn: 1, default: 0), "yogaNodeStyleSetFloat ABI drift");
_Static_assert(_Generic(&yogaNodeStyleSetBorder, opentui_yoga_node_style_set_border_fn: 1, default: 0), "yogaNodeStyleSetBorder ABI drift");
_Static_assert(_Generic(&yogaNodeSetMeasureFunc, opentui_yoga_node_set_measure_func_fn: 1, default: 0), "yogaNodeSetMeasureFunc ABI drift");
_Static_assert(_Generic(&yogaNodeUnsetMeasureFunc, opentui_yoga_node_unset_measure_func_fn: 1, default: 0), "yogaNodeUnsetMeasureFunc ABI drift");
_Static_assert(_Generic(&yogaNodeHasMeasureFunc, opentui_yoga_node_has_measure_func_fn: 1, default: 0), "yogaNodeHasMeasureFunc ABI drift");
_Static_assert(_Generic(&yogaSetMeasureCallback, opentui_yoga_set_measure_callback_fn: 1, default: 0), "yogaSetMeasureCallback ABI drift");
_Static_assert(_Generic(&yogaStoreMeasureResult, opentui_yoga_store_measure_result_fn: 1, default: 0), "yogaStoreMeasureResult ABI drift");
_Static_assert(_Generic(&createNativeRenderable, opentui_create_native_renderable_fn: 1, default: 0), "createNativeRenderable ABI drift");
_Static_assert(_Generic(&destroyNativeRenderable, opentui_destroy_native_renderable_fn: 1, default: 0), "destroyNativeRenderable ABI drift");
_Static_assert(_Generic(&nativeRenderableAttachYogaNode, opentui_native_renderable_attach_yoga_node_fn: 1, default: 0), "nativeRenderableAttachYogaNode ABI drift");
_Static_assert(_Generic(&nativeRenderableSetMeasureTarget, opentui_native_renderable_set_measure_target_fn: 1, default: 0), "nativeRenderableSetMeasureTarget ABI drift");
_Static_assert(_Generic(&createTextBuffer, opentui_create_text_buffer_fn: 1, default: 0), "createTextBuffer ABI drift");
_Static_assert(_Generic(&destroyTextBuffer, opentui_destroy_text_buffer_fn: 1, default: 0), "destroyTextBuffer ABI drift");
_Static_assert(_Generic(&textBufferGetLength, opentui_text_buffer_get_length_fn: 1, default: 0), "textBufferGetLength ABI drift");
_Static_assert(_Generic(&textBufferGetByteSize, opentui_text_buffer_get_byte_size_fn: 1, default: 0), "textBufferGetByteSize ABI drift");
_Static_assert(_Generic(&textBufferGetLineCount, opentui_text_buffer_get_line_count_fn: 1, default: 0), "textBufferGetLineCount ABI drift");
_Static_assert(_Generic(&textBufferGetTabWidth, opentui_text_buffer_get_tab_width_fn: 1, default: 0), "textBufferGetTabWidth ABI drift");
_Static_assert(_Generic(&textBufferReset, opentui_text_buffer_reset_fn: 1, default: 0), "textBufferReset ABI drift");
_Static_assert(_Generic(&textBufferClear, opentui_text_buffer_clear_fn: 1, default: 0), "textBufferClear ABI drift");
_Static_assert(_Generic(&textBufferLoadFile, opentui_text_buffer_load_file_fn: 1, default: 0), "textBufferLoadFile ABI drift");
_Static_assert(_Generic(&textBufferSetTabWidth, opentui_text_buffer_set_tab_width_fn: 1, default: 0), "textBufferSetTabWidth ABI drift");
_Static_assert(_Generic(&textBufferAppend, opentui_text_buffer_append_fn: 1, default: 0), "textBufferAppend ABI drift");
_Static_assert(_Generic(&textBufferRegisterMemBuffer, opentui_text_buffer_register_mem_buffer_fn: 1, default: 0), "textBufferRegisterMemBuffer ABI drift");
_Static_assert(_Generic(&textBufferReplaceMemBuffer, opentui_text_buffer_replace_mem_buffer_fn: 1, default: 0), "textBufferReplaceMemBuffer ABI drift");
_Static_assert(_Generic(&textBufferSetTextFromMem, opentui_text_buffer_set_text_from_mem_fn: 1, default: 0), "textBufferSetTextFromMem ABI drift");
_Static_assert(_Generic(&textBufferSetDefaultFg, opentui_text_buffer_set_default_fg_fn: 1, default: 0), "textBufferSetDefaultFg ABI drift");
_Static_assert(_Generic(&textBufferSetDefaultBg, opentui_text_buffer_set_default_bg_fn: 1, default: 0), "textBufferSetDefaultBg ABI drift");
_Static_assert(_Generic(&textBufferSetDefaultAttributes, opentui_text_buffer_set_default_attributes_fn: 1, default: 0), "textBufferSetDefaultAttributes ABI drift");
_Static_assert(_Generic(&textBufferResetDefaults, opentui_text_buffer_reset_defaults_fn: 1, default: 0), "textBufferResetDefaults ABI drift");
_Static_assert(_Generic(&textBufferSetStyledText, opentui_text_buffer_set_styled_text_fn: 1, default: 0), "textBufferSetStyledText ABI drift");
_Static_assert(_Generic(&textBufferClearAllHighlights, opentui_text_buffer_clear_all_highlights_fn: 1, default: 0), "textBufferClearAllHighlights ABI drift");
_Static_assert(_Generic(&textBufferAddHighlightByCharRange, opentui_text_buffer_add_highlight_by_char_range_fn: 1, default: 0), "textBufferAddHighlightByCharRange ABI drift");
_Static_assert(_Generic(&textBufferAddHighlight, opentui_text_buffer_add_highlight_fn: 1, default: 0), "textBufferAddHighlight ABI drift");
_Static_assert(_Generic(&textBufferRemoveHighlightsByRef, opentui_text_buffer_remove_highlights_by_ref_fn: 1, default: 0), "textBufferRemoveHighlightsByRef ABI drift");
_Static_assert(_Generic(&textBufferClearLineHighlights, opentui_text_buffer_clear_line_highlights_fn: 1, default: 0), "textBufferClearLineHighlights ABI drift");
_Static_assert(_Generic(&textBufferSetSyntaxStyle, opentui_text_buffer_set_syntax_style_fn: 1, default: 0), "textBufferSetSyntaxStyle ABI drift");
_Static_assert(_Generic(&createSyntaxStyle, opentui_create_syntax_style_fn: 1, default: 0), "createSyntaxStyle ABI drift");
_Static_assert(_Generic(&destroySyntaxStyle, opentui_destroy_syntax_style_fn: 1, default: 0), "destroySyntaxStyle ABI drift");
_Static_assert(_Generic(&syntaxStyleRegister, opentui_syntax_style_register_fn: 1, default: 0), "syntaxStyleRegister ABI drift");
_Static_assert(_Generic(&syntaxStyleResolveByName, opentui_syntax_style_resolve_fn: 1, default: 0), "syntaxStyleResolveByName ABI drift");
_Static_assert(_Generic(&syntaxStyleGetStyleCount, opentui_syntax_style_count_fn: 1, default: 0), "syntaxStyleGetStyleCount ABI drift");
_Static_assert(_Generic(&createTextBufferView, opentui_create_text_buffer_view_fn: 1, default: 0), "createTextBufferView ABI drift");
_Static_assert(_Generic(&destroyTextBufferView, opentui_destroy_text_buffer_view_fn: 1, default: 0), "destroyTextBufferView ABI drift");
_Static_assert(_Generic(&textBufferViewSetWrapWidth, opentui_text_buffer_view_set_wrap_width_fn: 1, default: 0), "textBufferViewSetWrapWidth ABI drift");
_Static_assert(_Generic(&textBufferViewSetWrapMode, opentui_text_buffer_view_set_wrap_mode_fn: 1, default: 0), "textBufferViewSetWrapMode ABI drift");
_Static_assert(_Generic(&textBufferViewSetFirstLineOffset, opentui_text_buffer_view_set_first_line_offset_fn: 1, default: 0), "textBufferViewSetFirstLineOffset ABI drift");
_Static_assert(_Generic(&textBufferViewSetSelection, opentui_text_buffer_view_set_selection_fn: 1, default: 0), "textBufferViewSetSelection ABI drift");
_Static_assert(_Generic(&textBufferViewUpdateSelection, opentui_text_buffer_view_update_selection_fn: 1, default: 0), "textBufferViewUpdateSelection ABI drift");
_Static_assert(_Generic(&textBufferViewResetSelection, opentui_text_buffer_view_reset_selection_fn: 1, default: 0), "textBufferViewResetSelection ABI drift");
_Static_assert(_Generic(&textBufferViewGetSelectionInfo, opentui_text_buffer_view_get_selection_info_fn: 1, default: 0), "textBufferViewGetSelectionInfo ABI drift");
_Static_assert(_Generic(&textBufferViewSetLocalSelection, opentui_text_buffer_view_set_local_selection_fn: 1, default: 0), "textBufferViewSetLocalSelection ABI drift");
_Static_assert(_Generic(&textBufferViewUpdateLocalSelection, opentui_text_buffer_view_update_local_selection_fn: 1, default: 0), "textBufferViewUpdateLocalSelection ABI drift");
_Static_assert(_Generic(&textBufferViewResetLocalSelection, opentui_text_buffer_view_reset_local_selection_fn: 1, default: 0), "textBufferViewResetLocalSelection ABI drift");
_Static_assert(_Generic(&textBufferViewGetSelectedText, opentui_text_buffer_view_get_selected_text_fn: 1, default: 0), "textBufferViewGetSelectedText ABI drift");
_Static_assert(_Generic(&textBufferViewSetViewportSize, opentui_text_buffer_view_set_viewport_size_fn: 1, default: 0), "textBufferViewSetViewportSize ABI drift");
_Static_assert(_Generic(&textBufferViewSetViewport, opentui_text_buffer_view_set_viewport_fn: 1, default: 0), "textBufferViewSetViewport ABI drift");
_Static_assert(_Generic(&textBufferViewGetVirtualLineCount, opentui_text_buffer_view_get_virtual_line_count_fn: 1, default: 0), "textBufferViewGetVirtualLineCount ABI drift");
_Static_assert(_Generic(&textBufferViewSetTabIndicator, opentui_text_buffer_view_set_tab_indicator_fn: 1, default: 0), "textBufferViewSetTabIndicator ABI drift");
_Static_assert(_Generic(&textBufferViewSetTabIndicatorColor, opentui_text_buffer_view_set_tab_indicator_color_fn: 1, default: 0), "textBufferViewSetTabIndicatorColor ABI drift");
_Static_assert(_Generic(&textBufferViewSetTruncate, opentui_text_buffer_view_set_truncate_fn: 1, default: 0), "textBufferViewSetTruncate ABI drift");
_Static_assert(_Generic(&textBufferViewMeasureForDimensions, opentui_text_buffer_view_measure_for_dimensions_fn: 1, default: 0), "textBufferViewMeasureForDimensions ABI drift");
_Static_assert(_Generic(&textBufferViewGetLineInfoDirect, opentui_text_buffer_view_get_line_info_direct_fn: 1, default: 0), "textBufferViewGetLineInfoDirect ABI drift");
_Static_assert(_Generic(&textBufferViewGetLogicalLineInfoDirect, opentui_text_buffer_view_get_logical_line_info_direct_fn: 1, default: 0), "textBufferViewGetLogicalLineInfoDirect ABI drift");
_Static_assert(_Generic(&getTerminalCapabilities, opentui_get_terminal_capabilities_fn: 1, default: 0), "getTerminalCapabilities ABI drift");
_Static_assert(_Generic(&processCapabilityResponse, opentui_process_capability_response_fn: 1, default: 0), "processCapabilityResponse ABI drift");
_Static_assert(_Generic(&createNativeSpanFeed, opentui_create_native_span_feed_fn: 1, default: 0), "createNativeSpanFeed ABI drift");
_Static_assert(_Generic(&attachNativeSpanFeed, opentui_span_feed_status_fn: 1, default: 0), "attachNativeSpanFeed ABI drift");
_Static_assert(_Generic(&streamClose, opentui_span_feed_status_fn: 1, default: 0), "streamClose ABI drift");
_Static_assert(_Generic(&destroyNativeSpanFeed, opentui_destroy_native_span_feed_fn: 1, default: 0), "destroyNativeSpanFeed ABI drift");
_Static_assert(_Generic(&streamWrite, opentui_span_feed_write_fn: 1, default: 0), "streamWrite ABI drift");
_Static_assert(_Generic(&streamCommit, opentui_span_feed_status_fn: 1, default: 0), "streamCommit ABI drift");
_Static_assert(_Generic(&streamReserve, opentui_span_feed_reserve_fn: 1, default: 0), "streamReserve ABI drift");
_Static_assert(_Generic(&streamCommitReserved, opentui_span_feed_commit_reserved_fn: 1, default: 0), "streamCommitReserved ABI drift");
_Static_assert(_Generic(&streamCancelReserved, opentui_span_feed_status_fn: 1, default: 0), "streamCancelReserved ABI drift");
_Static_assert(_Generic(&streamSetOptions, opentui_span_feed_options_fn: 1, default: 0), "streamSetOptions ABI drift");
_Static_assert(_Generic(&streamGetStats, opentui_span_feed_stats_fn: 1, default: 0), "streamGetStats ABI drift");
_Static_assert(_Generic(&streamDrainSpans, opentui_span_feed_drain_fn: 1, default: 0), "streamDrainSpans ABI drift");
_Static_assert(_Generic(&streamMarkSpanConsumed, opentui_span_feed_consume_fn: 1, default: 0), "streamMarkSpanConsumed ABI drift");
_Static_assert(_Generic(&streamSetCallback, opentui_span_feed_callback_fn: 1, default: 0), "streamSetCallback ABI drift");

#ifdef __cplusplus
}
#endif

#endif
