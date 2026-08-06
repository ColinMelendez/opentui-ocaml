#include <caml/mlvalues.h>
#include <caml/memory.h>

#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#include "opentui_abi.h"

enum {
  event_name_capacity = 64,
  event_data_capacity = 8,
};

static uint8_t captured_event_name[event_name_capacity];
static uint8_t captured_event_data[event_data_capacity];
static uint32_t captured_event_name_len;
static uint32_t captured_event_data_len;
static uint32_t captured_event_count;
static bool captured_event_overflow;

static void reset_event_capture(void) {
  memset(captured_event_name, 0, sizeof(captured_event_name));
  memset(captured_event_data, 0, sizeof(captured_event_data));
  captured_event_name_len = 0;
  captured_event_data_len = 0;
  captured_event_count = 0;
  captured_event_overflow = false;
}

static void capture_event(
    const uint8_t *name_ptr,
    uint32_t name_len,
    const uint8_t *data_ptr,
    uint32_t data_len) {
  captured_event_count += 1;
  if (name_len > sizeof(captured_event_name) || data_len > sizeof(captured_event_data)) {
    captured_event_overflow = true;
  }

  captured_event_name_len = name_len < sizeof(captured_event_name) ? name_len : sizeof(captured_event_name);
  captured_event_data_len = data_len < sizeof(captured_event_data) ? data_len : sizeof(captured_event_data);
  memcpy(captured_event_name, name_ptr, captured_event_name_len);
  memcpy(captured_event_data, data_ptr, captured_event_data_len);
}

CAMLprim value opentui_test_native_symbol_smoke(value unit_value) {
  CAMLparam1(unit_value);

  const bool invalid_renderer_options_rejected = createRenderer(0, 1, 1, 1, NULL) == 0 &&
      createRenderer(1, 0, 1, 1, NULL) == 0 && createRenderer(1, 1, 2, 1, NULL) == 0;
  const opentui_native_handle event_sink = createEventSink(NULL);
  const bool invalid_callback_rejected = event_sink == 0;

  destroyEventSink(event_sink);
  setUseThread(0, false);
  destroyRenderer(0);
  const bool invalid_handles_rejected = getCurrentBuffer(0) == 0 && getNextBuffer(0) == 0 &&
      getBufferWidth(0) == 0 && getBufferHeight(0) == 0;
  opentui_external_render_stats stats;
  getRenderStats(0, &stats);
  const bool invalid_stats_rejected = stats.frame_count == 0 && stats.cells_updated == 0 &&
      stats.average_cells_updated == 0 && !stats.render_time_valid && !stats.stdout_write_time_valid;

  bufferClear(0, NULL);
  const uint32_t resolved_length = bufferWriteResolvedChars(0, NULL, 0, false);
  bufferDrawText(0, NULL, 0, 0, 0, NULL, NULL, 0);
  bufferSetCell(0, 0, 0, 0, NULL, NULL, 0);

  CAMLreturn(Val_bool(invalid_renderer_options_rejected && invalid_callback_rejected &&
      invalid_handles_rejected && invalid_stats_rejected && resolved_length == 0));
}

CAMLprim value opentui_test_memory_renderer_round_trip(value unit_value) {
  CAMLparam1(unit_value);

  const opentui_native_handle renderer = createRenderer(2, 1, 1, 2, NULL);
  if (renderer == 0) {
    CAMLreturn(Val_false);
  }

  setUseThread(renderer, false);
  const opentui_native_handle current = getCurrentBuffer(renderer);
  const opentui_native_handle next = getNextBuffer(renderer);
  bool round_trip_succeeded =
      current != 0 && next != 0 && getBufferWidth(current) == 2 && getBufferHeight(current) == 1 &&
      getBufferWidth(next) == 2 && getBufferHeight(next) == 1;

  const uint16_t foreground[4] = {UINT16_C(255), UINT16_C(255), UINT16_C(255), UINT16_C(255)};
  const uint16_t background[4] = {0, 0, 0, UINT16_C(255)};
  const uint8_t text[3] = {'B', 'C', 'D'};
  uint8_t too_small_output[1] = {0};
  uint8_t output[2] = {0, 0};

  bufferClear(current, background);
  bufferDrawText(current, NULL, 0, 0, 0, foreground, background, 0);
  const uint32_t empty_output_length = bufferWriteResolvedChars(current, NULL, 0, false);
  bufferSetCell(current, 0, 0, UINT32_C(65), foreground, background, 0);
  bufferDrawText(current, text, sizeof(text), 1, 0, foreground, background, 0);
  const uint32_t too_small_length = bufferWriteResolvedChars(current, too_small_output, sizeof(too_small_output), false);
  const uint32_t output_length = bufferWriteResolvedChars(current, output, 2, false);
  round_trip_succeeded = round_trip_succeeded && too_small_length == 0 && output_length == 2 &&
      empty_output_length == 0 && output[0] == 'A' && output[1] == 'B';

  destroyRenderer(renderer);
  round_trip_succeeded = round_trip_succeeded && getCurrentBuffer(renderer) == 0 &&
      getNextBuffer(renderer) == 0 && getBufferWidth(current) == 0 && getBufferHeight(current) == 0 &&
      getBufferWidth(next) == 0 && getBufferHeight(next) == 0;

  CAMLreturn(Val_bool(round_trip_succeeded));
}

CAMLprim value opentui_test_event_callback_copy(value unit_value) {
  CAMLparam1(unit_value);

  reset_event_capture();
  const opentui_native_handle event_sink = createEventSink(capture_event);
  if (event_sink == 0) {
    CAMLreturn(Val_false);
  }

  const opentui_native_handle edit_buffer = createEditBuffer(1, event_sink);
  if (edit_buffer == 0) {
    destroyEventSink(event_sink);
    CAMLreturn(Val_false);
  }

  editBufferInsertText(edit_buffer, NULL, 0);
  const uint8_t text[1] = {'X'};
  editBufferInsertText(edit_buffer, text, 1);

  static const uint8_t expected_name[] = "eb_content-changed";
  const bool copied_payload = captured_event_count == 2 && !captured_event_overflow &&
      captured_event_name_len == sizeof(expected_name) - 1 &&
      memcmp(captured_event_name, expected_name, sizeof(expected_name) - 1) == 0 &&
      captured_event_data_len == 2;

  destroyEditBuffer(edit_buffer);
  destroyEventSink(event_sink);

  CAMLreturn(Val_bool(copied_payload));
}
