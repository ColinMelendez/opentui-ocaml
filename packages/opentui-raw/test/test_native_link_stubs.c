#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>

#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#include "opentui_abi.h"

static const uint32_t baseline_set_cell_calls = UINT32_C(1024);

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

  resizeRenderer(renderer, 3, 2);
  round_trip_succeeded = round_trip_succeeded &&
      getBufferWidth(current) == 3 && getBufferHeight(current) == 2 &&
      getBufferWidth(next) == 3 && getBufferHeight(next) == 2;

  destroyRenderer(renderer);
  round_trip_succeeded = round_trip_succeeded && getCurrentBuffer(renderer) == 0 &&
      getNextBuffer(renderer) == 0 && getBufferWidth(current) == 0 && getBufferHeight(current) == 0 &&
      getBufferWidth(next) == 0 && getBufferHeight(next) == 0;

  CAMLreturn(Val_bool(round_trip_succeeded));
}

CAMLprim value opentui_test_memory_output_bytes(value unit_value) {
  CAMLparam1(unit_value);
  CAMLlocal1(output);

  output = caml_alloc_string(0);
  const opentui_native_handle renderer = createRenderer(2, 1, 1, 2, NULL);
  if (renderer != 0) {
    setUseThread(renderer, false);
    const opentui_native_handle current = getCurrentBuffer(renderer);
    if (current != 0) {
      const uint16_t foreground[4] = {UINT16_C(255), UINT16_C(255), UINT16_C(255), UINT16_C(255)};
      const uint16_t background[4] = {0, 0, 0, UINT16_C(255)};

      output = caml_alloc_string(2);
      bufferSetCell(current, 0, 0, UINT32_C(65), foreground, background, 0);
      bufferSetCell(current, 1, 0, UINT32_C(66), foreground, background, 0);
      const uint32_t output_length = bufferWriteResolvedChars(
          current,
          (uint8_t *)Bytes_val(output),
          2,
          false);
      if (output_length != 2) {
        output = caml_alloc_string(0);
      }
    }
    destroyRenderer(renderer);
  }

  CAMLreturn(output);
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

CAMLprim value opentui_test_buffer_update_baseline(value unit_value) {
  CAMLparam1(unit_value);
  CAMLlocal1(result);

  uint32_t executed_set_cell_calls = 0;
  uint32_t executed_write_calls = 0;
  uint64_t active_allocations_before = 0;
  uint64_t active_allocations_after = 0;
  bool output_valid = false;

  const opentui_native_handle renderer = createRenderer(8, 1, 1, 2, NULL);
  if (renderer != 0) {
    setUseThread(renderer, false);
    const opentui_native_handle current = getCurrentBuffer(renderer);
    if (current != 0) {
      const uint16_t foreground[4] = {UINT16_C(255), UINT16_C(255), UINT16_C(255), UINT16_C(255)};
      const uint16_t background[4] = {0, 0, 0, UINT16_C(255)};
      uint8_t output[8] = {0};
      opentui_external_allocator_stats before;
      opentui_external_allocator_stats after;

      getAllocatorStats(&before);
      for (uint32_t call = 0; call < baseline_set_cell_calls; call += 1) {
        const uint32_t x = call % UINT32_C(8);
        const uint32_t character = UINT32_C(65) + (call % UINT32_C(26));
        bufferSetCell(current, x, 0, character, foreground, background, 0);
        executed_set_cell_calls += 1;
      }

      const uint32_t output_length = bufferWriteResolvedChars(current, output, sizeof(output), false);
      executed_write_calls = 1;
      getAllocatorStats(&after);

      output_valid = output_length == sizeof(output);
      for (uint32_t offset = 0; offset < sizeof(output); offset += 1) {
        const uint32_t character = UINT32_C(65) +
            ((baseline_set_cell_calls - UINT32_C(8) + offset) % UINT32_C(26));
        output_valid = output_valid && output[offset] == character;
      }
      active_allocations_before = before.active_allocations;
      active_allocations_after = after.active_allocations;
    }
    destroyRenderer(renderer);
  }

  result = caml_alloc_tuple(5);
  Store_field(result, 0, Val_int(executed_set_cell_calls));
  Store_field(result, 1, Val_int(executed_write_calls));
  Store_field(result, 2, caml_copy_int64(active_allocations_before));
  Store_field(result, 3, caml_copy_int64(active_allocations_after));
  Store_field(result, 4, Val_bool(output_valid));
  CAMLreturn(result);
}
