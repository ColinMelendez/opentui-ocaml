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
