#include <caml/mlvalues.h>
#include <caml/memory.h>

#include <stdint.h>

#include "opentui_abi.h"

CAMLprim value opentui_test_native_symbol_smoke(value unit_value) {
  CAMLparam1(unit_value);

  const bool invalid_dimensions_rejected = createRenderer(0, 1, 1, 1, NULL) == 0 &&
      createRenderer(1, 0, 1, 1, NULL) == 0;
  const opentui_native_handle event_sink = createEventSink(NULL);

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

  CAMLreturn(Val_bool(invalid_dimensions_rejected && invalid_handles_rejected && invalid_stats_rejected &&
      resolved_length == 0));
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
  const uint8_t text[1] = {'B'};
  uint8_t too_small_output[1] = {0};
  uint8_t output[2] = {0, 0};

  bufferClear(current, background);
  bufferSetCell(current, 0, 0, UINT32_C(65), foreground, background, 0);
  bufferDrawText(current, text, 1, 1, 0, foreground, background, 0);
  const uint32_t too_small_length = bufferWriteResolvedChars(current, too_small_output, 1, false);
  const uint32_t output_length = bufferWriteResolvedChars(current, output, 2, false);
  round_trip_succeeded = round_trip_succeeded && too_small_length == 0 && output_length == 2 &&
      output[0] == 'A' && output[1] == 'B';

  destroyRenderer(renderer);
  round_trip_succeeded = round_trip_succeeded && getCurrentBuffer(renderer) == 0 &&
      getNextBuffer(renderer) == 0 && getBufferWidth(current) == 0 && getBufferHeight(current) == 0 &&
      getBufferWidth(next) == 0 && getBufferHeight(next) == 0;

  CAMLreturn(Val_bool(round_trip_succeeded));
}
