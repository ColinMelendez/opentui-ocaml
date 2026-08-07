#ifndef OPENTUI_RAW_ABI_H
#define OPENTUI_RAW_ABI_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef uint32_t opentui_native_handle;

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
void destroyRenderer(opentui_native_handle renderer_handle);
opentui_native_handle getCurrentBuffer(opentui_native_handle renderer_handle);
opentui_native_handle getNextBuffer(opentui_native_handle renderer_handle);

uint32_t getBufferWidth(opentui_native_handle buffer_handle);
uint32_t getBufferHeight(opentui_native_handle buffer_handle);
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

void getRenderStats(
    opentui_native_handle renderer_handle,
    opentui_external_render_stats *output);
void getAllocatorStats(opentui_external_allocator_stats *output);

opentui_yoga_config_ref yogaConfigCreate(void);
void yogaConfigFree(opentui_yoga_config_ref config);
opentui_yoga_node_ref yogaNodeCreateWithConfig(opentui_yoga_config_const_ref config);
void yogaNodeFreeRecursive(opentui_yoga_node_ref node);
void yogaNodeInsertChild(opentui_yoga_node_ref node, opentui_yoga_node_ref child, uint32_t index);
uint32_t yogaNodeGetChildCount(opentui_yoga_node_const_ref node);
void yogaNodeCalculateLayout(opentui_yoga_node_ref node, float width, float height, uint32_t direction);
void yogaNodeGetComputedLayout(
    opentui_yoga_node_const_ref node,
    opentui_external_yoga_layout *output);
void yogaNodeStyleSetValue(
    opentui_yoga_node_ref node,
    uint32_t kind,
    uint32_t edge_or_gutter,
    uint32_t unit,
    float value);

void getTerminalCapabilities(
    opentui_native_handle renderer_handle,
    opentui_external_capabilities *output);
void processCapabilityResponse(
    opentui_native_handle renderer_handle,
    const uint8_t *response_ptr,
    uint32_t response_len);

_Static_assert(sizeof(opentui_native_handle) == 4, "OpenTUI handles must be u32");
_Static_assert(sizeof(bool) == 1, "OpenTUI bool must have one-byte C ABI storage");
_Static_assert(sizeof(opentui_external_build_options) == 2, "build options ABI drift");
_Static_assert(sizeof(opentui_external_allocator_stats) == 40, "allocator stats ABI drift");
_Static_assert(sizeof(opentui_external_render_stats) == 56, "render stats ABI drift");
_Static_assert(sizeof(opentui_external_yoga_layout) == 24, "Yoga layout ABI drift");
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

typedef opentui_native_handle (*opentui_create_event_sink_fn)(opentui_event_callback);
typedef void (*opentui_destroy_event_sink_fn)(opentui_native_handle);
typedef opentui_native_handle (*opentui_create_edit_buffer_fn)(uint8_t, opentui_native_handle);
typedef void (*opentui_destroy_edit_buffer_fn)(opentui_native_handle);
typedef void (*opentui_edit_buffer_insert_text_fn)(opentui_native_handle, const uint8_t *, uint32_t);
typedef opentui_native_handle (*opentui_create_renderer_fn)(uint32_t, uint32_t, uint8_t, uint8_t, void *);
typedef void (*opentui_set_use_thread_fn)(opentui_native_handle, bool);
typedef void (*opentui_destroy_renderer_fn)(opentui_native_handle);
typedef opentui_native_handle (*opentui_get_buffer_fn)(opentui_native_handle);
typedef uint32_t (*opentui_get_buffer_dimension_fn)(opentui_native_handle);
typedef void (*opentui_buffer_clear_fn)(opentui_native_handle, const uint16_t *);
typedef uint32_t (*opentui_buffer_write_fn)(opentui_native_handle, uint8_t *, uint32_t, bool);
typedef void (*opentui_buffer_draw_text_fn)(opentui_native_handle, const uint8_t *, uint32_t, uint32_t, uint32_t, const uint16_t *, const uint16_t *, uint32_t);
typedef void (*opentui_buffer_set_cell_fn)(opentui_native_handle, uint32_t, uint32_t, uint32_t, const uint16_t *, const uint16_t *, uint32_t);
typedef void (*opentui_get_render_stats_fn)(opentui_native_handle, opentui_external_render_stats *);
typedef void (*opentui_get_allocator_stats_fn)(opentui_external_allocator_stats *);
typedef opentui_yoga_config_ref (*opentui_yoga_config_create_fn)(void);
typedef void (*opentui_yoga_config_free_fn)(opentui_yoga_config_ref);
typedef opentui_yoga_node_ref (*opentui_yoga_node_create_with_config_fn)(opentui_yoga_config_const_ref);
typedef void (*opentui_yoga_node_free_recursive_fn)(opentui_yoga_node_ref);
typedef void (*opentui_yoga_node_insert_child_fn)(opentui_yoga_node_ref, opentui_yoga_node_ref, uint32_t);
typedef uint32_t (*opentui_yoga_node_get_child_count_fn)(opentui_yoga_node_const_ref);
typedef void (*opentui_yoga_node_calculate_layout_fn)(opentui_yoga_node_ref, float, float, uint32_t);
typedef void (*opentui_yoga_node_get_computed_layout_fn)(opentui_yoga_node_const_ref, opentui_external_yoga_layout *);
typedef void (*opentui_yoga_node_style_set_value_fn)(opentui_yoga_node_ref, uint32_t, uint32_t, uint32_t, float);
typedef void (*opentui_get_terminal_capabilities_fn)(opentui_native_handle, opentui_external_capabilities *);
typedef void (*opentui_process_capability_response_fn)(opentui_native_handle, const uint8_t *, uint32_t);

_Static_assert(_Generic(&createEventSink, opentui_create_event_sink_fn: 1, default: 0), "createEventSink ABI drift");
_Static_assert(_Generic(&destroyEventSink, opentui_destroy_event_sink_fn: 1, default: 0), "destroyEventSink ABI drift");
_Static_assert(_Generic(&createEditBuffer, opentui_create_edit_buffer_fn: 1, default: 0), "createEditBuffer ABI drift");
_Static_assert(_Generic(&destroyEditBuffer, opentui_destroy_edit_buffer_fn: 1, default: 0), "destroyEditBuffer ABI drift");
_Static_assert(_Generic(&editBufferInsertText, opentui_edit_buffer_insert_text_fn: 1, default: 0), "editBufferInsertText ABI drift");
_Static_assert(_Generic(&createRenderer, opentui_create_renderer_fn: 1, default: 0), "createRenderer ABI drift");
_Static_assert(_Generic(&setUseThread, opentui_set_use_thread_fn: 1, default: 0), "setUseThread ABI drift");
_Static_assert(_Generic(&destroyRenderer, opentui_destroy_renderer_fn: 1, default: 0), "destroyRenderer ABI drift");
_Static_assert(_Generic(&getCurrentBuffer, opentui_get_buffer_fn: 1, default: 0), "getCurrentBuffer ABI drift");
_Static_assert(_Generic(&getNextBuffer, opentui_get_buffer_fn: 1, default: 0), "getNextBuffer ABI drift");
_Static_assert(_Generic(&getBufferWidth, opentui_get_buffer_dimension_fn: 1, default: 0), "getBufferWidth ABI drift");
_Static_assert(_Generic(&getBufferHeight, opentui_get_buffer_dimension_fn: 1, default: 0), "getBufferHeight ABI drift");
_Static_assert(_Generic(&bufferClear, opentui_buffer_clear_fn: 1, default: 0), "bufferClear ABI drift");
_Static_assert(_Generic(&bufferWriteResolvedChars, opentui_buffer_write_fn: 1, default: 0), "bufferWriteResolvedChars ABI drift");
_Static_assert(_Generic(&bufferDrawText, opentui_buffer_draw_text_fn: 1, default: 0), "bufferDrawText ABI drift");
_Static_assert(_Generic(&bufferSetCell, opentui_buffer_set_cell_fn: 1, default: 0), "bufferSetCell ABI drift");
_Static_assert(_Generic(&getRenderStats, opentui_get_render_stats_fn: 1, default: 0), "getRenderStats ABI drift");
_Static_assert(_Generic(&getAllocatorStats, opentui_get_allocator_stats_fn: 1, default: 0), "getAllocatorStats ABI drift");
_Static_assert(_Generic(&yogaConfigCreate, opentui_yoga_config_create_fn: 1, default: 0), "yogaConfigCreate ABI drift");
_Static_assert(_Generic(&yogaConfigFree, opentui_yoga_config_free_fn: 1, default: 0), "yogaConfigFree ABI drift");
_Static_assert(_Generic(&yogaNodeCreateWithConfig, opentui_yoga_node_create_with_config_fn: 1, default: 0), "yogaNodeCreateWithConfig ABI drift");
_Static_assert(_Generic(&yogaNodeFreeRecursive, opentui_yoga_node_free_recursive_fn: 1, default: 0), "yogaNodeFreeRecursive ABI drift");
_Static_assert(_Generic(&yogaNodeInsertChild, opentui_yoga_node_insert_child_fn: 1, default: 0), "yogaNodeInsertChild ABI drift");
_Static_assert(_Generic(&yogaNodeGetChildCount, opentui_yoga_node_get_child_count_fn: 1, default: 0), "yogaNodeGetChildCount ABI drift");
_Static_assert(_Generic(&yogaNodeCalculateLayout, opentui_yoga_node_calculate_layout_fn: 1, default: 0), "yogaNodeCalculateLayout ABI drift");
_Static_assert(_Generic(&yogaNodeGetComputedLayout, opentui_yoga_node_get_computed_layout_fn: 1, default: 0), "yogaNodeGetComputedLayout ABI drift");
_Static_assert(_Generic(&yogaNodeStyleSetValue, opentui_yoga_node_style_set_value_fn: 1, default: 0), "yogaNodeStyleSetValue ABI drift");
_Static_assert(_Generic(&getTerminalCapabilities, opentui_get_terminal_capabilities_fn: 1, default: 0), "getTerminalCapabilities ABI drift");
_Static_assert(_Generic(&processCapabilityResponse, opentui_process_capability_response_fn: 1, default: 0), "processCapabilityResponse ABI drift");

#ifdef __cplusplus
}
#endif

#endif
