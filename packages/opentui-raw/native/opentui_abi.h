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

_Static_assert(sizeof(opentui_native_handle) == 4, "OpenTUI handles must be u32");
_Static_assert(sizeof(bool) == 1, "OpenTUI bool must have one-byte C ABI storage");
_Static_assert(sizeof(opentui_external_build_options) == 2, "build options ABI drift");
_Static_assert(sizeof(opentui_external_render_stats) == 56, "render stats ABI drift");
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

#ifdef __cplusplus
}
#endif

#endif
