#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#include <stdbool.h>
#include <math.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#include "native/opentui_abi.h"
#include "raw_status.h"

extern void *opentui_raw_span_feed_pointer(uint32_t token);

static value make_status_handle(int status, opentui_native_handle handle) {
  CAMLparam0();
  CAMLlocal3(result, status_value, handle_value);

  status_value = Val_int(status);
  handle_value = caml_copy_int32((int32_t)handle);
  result = caml_alloc_tuple(2);
  Store_field(result, 0, status_value);
  Store_field(result, 1, handle_value);
  CAMLreturn(result);
}

static value make_status_dimensions(
    int status,
    uint32_t width,
    uint32_t height) {
  CAMLparam0();
  CAMLlocal4(result, status_value, width_value, height_value);

  status_value = Val_int(status);
  width_value = caml_copy_int32((int32_t)width);
  height_value = caml_copy_int32((int32_t)height);
  result = caml_alloc_tuple(3);
  Store_field(result, 0, status_value);
  Store_field(result, 1, width_value);
  Store_field(result, 2, height_value);
  CAMLreturn(result);
}

static value make_status_count(int status, uint32_t count) {
  CAMLparam0();
  CAMLlocal3(result, status_value, count_value);

  status_value = Val_int(status);
  count_value = caml_copy_int32((int32_t)count);
  result = caml_alloc_tuple(2);
  Store_field(result, 0, status_value);
  Store_field(result, 1, count_value);
  CAMLreturn(result);
}

static value make_status_bool(int status, bool flag) {
  CAMLparam0();
  CAMLlocal3(result, status_value, flag_value);

  status_value = Val_int(status);
  flag_value = Val_bool(flag);
  result = caml_alloc_tuple(2);
  Store_field(result, 0, status_value);
  Store_field(result, 1, flag_value);
  CAMLreturn(result);
}

static bool buffer_is_valid(opentui_native_handle handle) {
  return handle != 0 && getBufferWidth(handle) != 0;
}

static bool optimized_buffer_is_valid(opentui_native_handle handle) {
  return buffer_is_valid(handle);
}

static bool renderer_is_valid(opentui_native_handle handle) {
  return handle != 0 && getCurrentBuffer(handle) != 0;
}

CAMLprim value opentui_raw_optimized_buffer_as_buffer(value handle_value) {
  CAMLparam1(handle_value);
  CAMLreturn(handle_value);
}

static bool read_int32_array(
    value array_value,
    int32_t **output,
    uint32_t *length) {
  if (!Is_block(array_value) || Tag_val(array_value) != 0) {
    return false;
  }

  mlsize_t array_length = Wosize_val(array_value);
  if (array_length > UINT32_MAX) {
    return false;
  }

  *length = (uint32_t)array_length;
  if (array_length == 0) {
    *output = NULL;
    return true;
  }

  int32_t *values = caml_stat_alloc(array_length * sizeof(*values));
  for (mlsize_t index = 0; index < array_length; index++) {
    value element = Field(array_value, index);
    if (!Is_block(element) || Tag_val(element) != Custom_tag) {
      caml_stat_free(values);
      return false;
    }
    values[index] = Int32_val(element);
  }

  *output = values;
  return true;
}

static bool read_grayscale_floatarray(
    value array_value,
    uint32_t width,
    uint32_t height,
    float **output) {
  if (!Is_block(array_value) || Tag_val(array_value) != Double_array_tag) {
    return false;
  }

  uint64_t array_length = (uint64_t)Wosize_val(array_value);
  uint64_t expected_length = (uint64_t)width * (uint64_t)height;
  if (array_length != expected_length
      || expected_length > SIZE_MAX / sizeof(float)) {
    return false;
  }

  float *values = NULL;
  if (expected_length > 0) {
    values = caml_stat_alloc((size_t)expected_length * sizeof(*values));
  }
  for (uint64_t index = 0; index < expected_length; index++) {
    double input = Double_field(array_value, (mlsize_t)index);
    if (!isfinite(input)) {
      if (values != NULL) caml_stat_free(values);
      return false;
    }
    values[index] = (float)input;
  }
  *output = values;
  return true;
}

static bool renderer_buffers_have_dimensions(
    opentui_native_handle renderer,
    uint32_t width,
    uint32_t height) {
  opentui_native_handle current = getCurrentBuffer(renderer);
  opentui_native_handle next = getNextBuffer(renderer);
  return current != 0 && next != 0
      && getBufferWidth(current) == width
      && getBufferHeight(current) == height
      && getBufferWidth(next) == width
      && getBufferHeight(next) == height;
}

static bool read_color(value color, uint16_t output[4]) {
  if (!Is_block(color) || Wosize_val(color) != 4) {
    return false;
  }

  for (uintnat index = 0; index < 4; index++) {
    value channel = Field(color, index);
    if (!Is_long(channel)) {
      return false;
    }

    intnat channel_value = Long_val(channel);
    if (channel_value < 0 || channel_value > UINT8_MAX) {
      return false;
    }

    output[index] = (uint16_t)channel_value;
  }

  return true;
}

static bool read_optional_code(
    value optional,
    uint8_t maximum,
    uint8_t sentinel,
    uint8_t *output) {
  if (Is_long(optional)) {
    if (Long_val(optional) != 0) {
      return false;
    }
    *output = sentinel;
    return true;
  }

  if (Wosize_val(optional) != 1) {
    return false;
  }
  value code = Field(optional, 0);
  if (!Is_long(code)) {
    return false;
  }

  intnat code_value = Long_val(code);
  if (code_value < 0 || code_value > maximum) {
    return false;
  }
  *output = (uint8_t)code_value;
  return true;
}

static bool read_optional_bool(value optional, uint8_t *output) {
  return read_optional_code(optional, 1, UINT8_MAX, output);
}

static bool read_optional_color(
    value optional,
    uint16_t output[4],
    const uint16_t **pointer) {
  if (Is_long(optional)) {
    if (Long_val(optional) != 0) {
      return false;
    }
    *pointer = NULL;
    return true;
  }

  if (Wosize_val(optional) != 1 || !read_color(Field(optional, 0), output)) {
    return false;
  }
  *pointer = output;
  return true;
}

static uint8_t cursor_channel(float channel) {
  if (!isfinite(channel) || channel <= 0.0f) {
    return 0;
  }
  if (channel >= 1.0f) {
    return UINT8_MAX;
  }
  return (uint8_t)lroundf(channel * 255.0f);
}

static value make_status_cursor_state(
    int status,
    const opentui_external_cursor_state *state) {
  CAMLparam0();
  CAMLlocal3(result, state_value, color_value);

  uint32_t x = state == NULL ? 0 : state->x;
  uint32_t y = state == NULL ? 0 : state->y;
  bool visible = state != NULL && state->visible;
  uint8_t style = state == NULL ? 3 : state->style;
  bool blinking = state != NULL && state->blinking;
  uint8_t red = state == NULL ? 0 : cursor_channel(state->r);
  uint8_t green = state == NULL ? 0 : cursor_channel(state->g);
  uint8_t blue = state == NULL ? 0 : cursor_channel(state->b);
  uint8_t alpha = state == NULL ? 0 : cursor_channel(state->a);

  color_value = caml_alloc_tuple(4);
  Store_field(color_value, 0, Val_int(red));
  Store_field(color_value, 1, Val_int(green));
  Store_field(color_value, 2, Val_int(blue));
  Store_field(color_value, 3, Val_int(alpha));

  state_value = caml_alloc_tuple(6);
  Store_field(state_value, 0, caml_copy_int32((int32_t)x));
  Store_field(state_value, 1, caml_copy_int32((int32_t)y));
  Store_field(state_value, 2, Val_bool(visible));
  Store_field(state_value, 3, Val_int(style));
  Store_field(state_value, 4, Val_bool(blinking));
  Store_field(state_value, 5, color_value);

  result = caml_alloc_tuple(2);
  Store_field(result, 0, Val_int(status));
  Store_field(result, 1, state_value);
  CAMLreturn(result);
}

static bool read_text_length(value text, uint32_t *length) {
  mlsize_t text_length = caml_string_length(text);
  if (text_length > UINT32_MAX) {
    return false;
  }

  *length = (uint32_t)text_length;
  return true;
}

static bool read_border_chars(value chars, uint32_t output[11]) {
  if (!Is_block(chars) || Wosize_val(chars) != 11) {
    return false;
  }

  for (uintnat index = 0; index < 11; index++) {
    value codepoint = Field(chars, index);
    if (!Is_block(codepoint) || Tag_val(codepoint) != Custom_tag) {
      return false;
    }

    int32_t codepoint_value = Int32_val(codepoint);
    if (codepoint_value < 0) {
      return false;
    }
    output[index] = (uint32_t)codepoint_value;
  }
  return true;
}

static bool read_optional_text(
    value optional_text,
    const uint8_t **data,
    uint32_t *length) {
  if (Is_long(optional_text)) {
    if (Long_val(optional_text) != 0) {
      return false;
    }
    *data = NULL;
    *length = 0;
    return true;
  }

  if (Wosize_val(optional_text) != 1) {
    return false;
  }
  value text = Field(optional_text, 0);
  if (!Is_block(text) || Tag_val(text) != String_tag
      || !read_text_length(text, length)) {
    return false;
  }

  *data = (const uint8_t *)String_val(text);
  return true;
}

CAMLprim value opentui_raw_renderer_create(
    value width_value,
    value height_value,
    value buffered_destination_value,
    value remote_mode_value,
    value feed_value) {
  CAMLparam5(
      width_value,
      height_value,
      buffered_destination_value,
      remote_mode_value,
      feed_value);

  int32_t width = Int32_val(width_value);
  int32_t height = Int32_val(height_value);
  int buffered_destination = Int_val(buffered_destination_value);
  int remote_mode = Int_val(remote_mode_value);
  if (width <= 0 || height <= 0) {
    CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_INVALID_ARGUMENT, 0));
  }
  if (buffered_destination < 0 || buffered_destination > 1
      || remote_mode < 0 || remote_mode > 2) {
    CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_INVALID_ARGUMENT, 0));
  }

  void *feed_pointer = NULL;
  if (!Is_long(feed_value)) {
    if (Wosize_val(feed_value) != 1) {
      CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_INVALID_ARGUMENT, 0));
    }
    value token_value = Field(feed_value, 0);
    if (!Is_block(token_value) || Tag_val(token_value) != Custom_tag) {
      CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_INVALID_ARGUMENT, 0));
    }
    feed_pointer = opentui_raw_span_feed_pointer((uint32_t)Int32_val(token_value));
    if (feed_pointer == NULL) {
      CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_STALE_HANDLE, 0));
    }
  } else if (Int_val(feed_value) != 0) {
    CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_INVALID_ARGUMENT, 0));
  }

  opentui_native_handle handle =
      createRenderer(
          (uint32_t)width,
          (uint32_t)height,
          (uint8_t)buffered_destination,
          (uint8_t)remote_mode,
          feed_pointer);
  if (handle == 0) {
    CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_NATIVE_FAILURE, 0));
  }

  setUseThread(handle, false);
  CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_OK, handle));
}

CAMLprim value opentui_raw_renderer_resize(
    value handle_value,
    value width_value,
    value height_value) {
  CAMLparam3(handle_value, width_value, height_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  int32_t width = Int32_val(width_value);
  int32_t height = Int32_val(height_value);
  if (handle == 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (width <= 0 || height <= 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }
  if (getCurrentBuffer(handle) == 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }

  resizeRenderer(handle, (uint32_t)width, (uint32_t)height);
  if (!renderer_buffers_have_dimensions(
          handle, (uint32_t)width, (uint32_t)height)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_NATIVE_FAILURE));
  }
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_renderer_write_out(
    value handle_value,
    value bytes_value) {
  CAMLparam2(handle_value, bytes_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (!renderer_is_valid(handle)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }

  writeOut(handle, (const uint8_t *)Bytes_val(bytes_value),
           (uint32_t)caml_string_length(bytes_value));
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_renderer_query_terminal_capabilities(
    value handle_value) {
  CAMLparam1(handle_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (!renderer_is_valid(handle)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }

  queryTerminalCapabilities(handle);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_renderer_trigger_notification(
    value handle_value,
    value message_value,
    value title_value) {
  CAMLparam3(handle_value, message_value, title_value);
  CAMLlocal1(result);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  uint32_t message_length;
  const uint8_t *title;
  uint32_t title_length;
  if (!renderer_is_valid(handle)) {
    CAMLreturn(make_status_bool(OPENTUI_RAW_STATUS_STALE_HANDLE, false));
  }
  if (!Is_block(message_value) || Tag_val(message_value) != String_tag
      || !read_text_length(message_value, &message_length)
      || !read_optional_text(title_value, &title, &title_length)) {
    CAMLreturn(make_status_bool(OPENTUI_RAW_STATUS_INVALID_ARGUMENT, false));
  }

  bool triggered = triggerNotification(
      handle,
      (const uint8_t *)String_val(message_value),
      message_length,
      title,
      title_length);
  result = make_status_bool(OPENTUI_RAW_STATUS_OK, triggered);
  CAMLreturn(result);
}

CAMLprim value opentui_raw_renderer_destroy(value handle_value) {
  CAMLparam1(handle_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (handle != 0) {
    destroyRenderer(handle);
  }

  CAMLreturn(Val_unit);
}

CAMLprim value opentui_raw_renderer_buffer(value handle_value, value next_value) {
  CAMLparam2(handle_value, next_value);

  opentui_native_handle renderer =
      (opentui_native_handle)Int32_val(handle_value);
  if (renderer == 0) {
    CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_STALE_HANDLE, 0));
  }

  opentui_native_handle buffer =
      Bool_val(next_value) ? getNextBuffer(renderer) : getCurrentBuffer(renderer);
  if (buffer == 0) {
    CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_STALE_HANDLE, 0));
  }

  CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_OK, buffer));
}

CAMLprim value opentui_raw_renderer_render(value handle_value, value force_value) {
  CAMLparam2(handle_value, force_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (handle == 0) {
    CAMLreturn(Val_int(OPENTUI_RENDER_STATUS_FAILED));
  }

  CAMLreturn(Val_int((int)render(handle, Bool_val(force_value))));
}

static value make_split_render_result(uint64_t packed) {
  uint32_t offset = (uint32_t)(packed & UINT64_C(0xffffffff));
  int status = (int)((packed >> 32) & UINT64_C(0xff));
  return make_status_count(status, offset);
}

CAMLprim value opentui_raw_renderer_set_render_offset(
    value handle_value,
    value offset_value) {
  CAMLparam2(handle_value, offset_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  int32_t offset = Int32_val(offset_value);
  if (handle == 0 || !renderer_is_valid(handle)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (offset < 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  setRenderOffset(handle, (uint32_t)offset);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_renderer_reset_split_scrollback(
    value handle_value,
    value seed_rows_value,
    value pinned_render_offset_value) {
  CAMLparam3(handle_value, seed_rows_value, pinned_render_offset_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  int32_t seed_rows = Int32_val(seed_rows_value);
  int32_t pinned_render_offset = Int32_val(pinned_render_offset_value);
  if (handle == 0 || !renderer_is_valid(handle)) {
    CAMLreturn(make_status_count(OPENTUI_RAW_STATUS_STALE_HANDLE, 0));
  }
  if (seed_rows < 0 || pinned_render_offset < 0) {
    CAMLreturn(make_status_count(OPENTUI_RAW_STATUS_INVALID_ARGUMENT, 0));
  }

  CAMLreturn(make_status_count(
      OPENTUI_RAW_STATUS_OK,
      resetSplitScrollback(
          handle, (uint32_t)seed_rows, (uint32_t)pinned_render_offset)));
}

CAMLprim value opentui_raw_renderer_sync_split_scrollback(
    value handle_value,
    value pinned_render_offset_value) {
  CAMLparam2(handle_value, pinned_render_offset_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  int32_t pinned_render_offset = Int32_val(pinned_render_offset_value);
  if (handle == 0 || !renderer_is_valid(handle)) {
    CAMLreturn(make_status_count(OPENTUI_RAW_STATUS_STALE_HANDLE, 0));
  }
  if (pinned_render_offset < 0) {
    CAMLreturn(make_split_render_result(
        ((uint64_t)OPENTUI_RENDER_STATUS_FAILED) << 32));
  }

  CAMLreturn(make_status_count(
      OPENTUI_RAW_STATUS_OK,
      syncSplitScrollback(handle, (uint32_t)pinned_render_offset)));
}

CAMLprim value opentui_raw_renderer_get_split_output_offset(
    value handle_value,
    value surface_offset_value) {
  CAMLparam2(handle_value, surface_offset_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  int32_t surface_offset = Int32_val(surface_offset_value);
  if (handle == 0 || !renderer_is_valid(handle)) {
    CAMLreturn(make_status_count(OPENTUI_RAW_STATUS_STALE_HANDLE, 0));
  }
  if (surface_offset < 0) {
    CAMLreturn(make_status_count(OPENTUI_RAW_STATUS_INVALID_ARGUMENT, 0));
  }

  CAMLreturn(make_status_count(
      OPENTUI_RAW_STATUS_OK,
      getSplitOutputOffset(handle, (uint32_t)surface_offset)));
}

CAMLprim value opentui_raw_renderer_set_pending_split_footer_transition(
    value handle_value,
    value transition_value) {
  CAMLparam2(handle_value, transition_value);

  opentui_native_handle handle =
      (opentui_native_handle)Int32_val(handle_value);
  if (handle == 0 || !renderer_is_valid(handle)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (!Is_block(transition_value) || Wosize_val(transition_value) != 6) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  int32_t mode = Int32_val(Field(transition_value, 0));
  int32_t source_top_line = Int32_val(Field(transition_value, 1));
  int32_t source_height = Int32_val(Field(transition_value, 2));
  int32_t target_top_line = Int32_val(Field(transition_value, 3));
  int32_t target_height = Int32_val(Field(transition_value, 4));
  int32_t scroll_lines = Int32_val(Field(transition_value, 5));
  if (mode < 0 || mode > 2 || source_top_line < 0 || source_height < 0
      || target_top_line < 0 || target_height < 0 || scroll_lines < 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  setPendingSplitFooterTransition(
      handle, (uint8_t)mode, (uint32_t)source_top_line,
      (uint32_t)source_height, (uint32_t)target_top_line,
      (uint32_t)target_height, (uint32_t)scroll_lines);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_renderer_clear_pending_split_footer_transition(
    value handle_value) {
  CAMLparam1(handle_value);

  opentui_native_handle handle =
      (opentui_native_handle)Int32_val(handle_value);
  if (handle == 0 || !renderer_is_valid(handle)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }

  clearPendingSplitFooterTransition(handle);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_renderer_repaint_split_footer(
    value handle_value,
    value pinned_render_offset_value,
    value force_value) {
  CAMLparam3(handle_value, pinned_render_offset_value, force_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  int32_t pinned_render_offset = Int32_val(pinned_render_offset_value);
  if (handle == 0 || !renderer_is_valid(handle)) {
    CAMLreturn(make_split_render_result(
        ((uint64_t)OPENTUI_RENDER_STATUS_FAILED) << 32));
  }
  if (pinned_render_offset < 0) {
    CAMLreturn(make_split_render_result(
        ((uint64_t)OPENTUI_RENDER_STATUS_FAILED) << 32));
  }

  CAMLreturn(make_split_render_result(
      repaintSplitFooter(handle, (uint32_t)pinned_render_offset,
                         Bool_val(force_value))));
}

static value renderer_commit_split_footer_snapshot_impl(
    value handle_value,
    value snapshot_value,
    value row_columns_value,
    value start_on_new_line_value,
    value trailing_newline_value,
    value pinned_render_offset_value,
    value force_value,
    value begin_frame_value,
    value finalize_frame_value) {
  CAMLparam5(handle_value, snapshot_value, row_columns_value,
             start_on_new_line_value, trailing_newline_value);
  CAMLxparam4(pinned_render_offset_value, force_value, begin_frame_value,
              finalize_frame_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  opentui_native_handle snapshot =
      (opentui_native_handle)Int32_val(snapshot_value);
  int32_t row_columns = Int32_val(row_columns_value);
  int32_t pinned_render_offset = Int32_val(pinned_render_offset_value);
  if (handle == 0 || !renderer_is_valid(handle)
      || snapshot == 0 || !optimized_buffer_is_valid(snapshot)) {
    CAMLreturn(make_split_render_result(
        ((uint64_t)OPENTUI_RENDER_STATUS_FAILED) << 32));
  }
  if (row_columns < 0 || pinned_render_offset < 0) {
    CAMLreturn(make_split_render_result(
        ((uint64_t)OPENTUI_RENDER_STATUS_FAILED) << 32));
  }

  CAMLreturn(make_split_render_result(
      commitSplitFooterSnapshot(
          handle, snapshot, (uint32_t)row_columns,
          Bool_val(start_on_new_line_value), Bool_val(trailing_newline_value),
          (uint32_t)pinned_render_offset, Bool_val(force_value),
          Bool_val(begin_frame_value), Bool_val(finalize_frame_value))));
}

CAMLprim value opentui_raw_renderer_commit_split_footer_snapshot(
    value handle_value,
    value snapshot_value,
    value row_columns_value,
    value start_on_new_line_value,
    value trailing_newline_value,
    value pinned_render_offset_value,
    value force_value,
    value begin_frame_value,
    value finalize_frame_value) {
  return renderer_commit_split_footer_snapshot_impl(
      handle_value, snapshot_value, row_columns_value, start_on_new_line_value,
      trailing_newline_value, pinned_render_offset_value, force_value,
      begin_frame_value, finalize_frame_value);
}

CAMLprim value opentui_raw_renderer_commit_split_footer_snapshot_bytecode(
    value *arguments,
    int argument_count) {
  if (argument_count != 9) {
    caml_invalid_argument("opentui_raw_renderer_commit_split_footer_snapshot");
  }
  return renderer_commit_split_footer_snapshot_impl(
      arguments[0], arguments[1], arguments[2], arguments[3], arguments[4],
      arguments[5], arguments[6], arguments[7], arguments[8]);
}

CAMLprim value opentui_raw_renderer_set_background_color(
    value handle_value,
    value color_value) {
  CAMLparam2(handle_value, color_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  uint16_t color[4];
  if (!renderer_is_valid(handle)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (!read_color(color_value, color)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  setBackgroundColor(handle, color);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_renderer_set_cursor_position(
    value handle_value,
    value x_value,
    value y_value,
    value visible_value) {
  CAMLparam4(handle_value, x_value, y_value, visible_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (!renderer_is_valid(handle)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }

  setCursorPosition(
      handle,
      Int32_val(x_value),
      Int32_val(y_value),
      Bool_val(visible_value));
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_renderer_set_cursor_color(
    value handle_value,
    value color_value) {
  CAMLparam2(handle_value, color_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  uint16_t color[4];
  if (!renderer_is_valid(handle)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (!read_color(color_value, color)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  setCursorColor(handle, color);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_renderer_set_cursor_style_options(
    value handle_value,
    value style_value,
    value blinking_value,
    value color_value,
    value cursor_value) {
  CAMLparam5(handle_value, style_value, blinking_value, color_value, cursor_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  uint8_t style;
  uint8_t blinking;
  uint8_t cursor;
  uint16_t color[4];
  const uint16_t *color_pointer;
  if (!renderer_is_valid(handle)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (!read_optional_code(style_value, 3, UINT8_MAX, &style)
      || !read_optional_bool(blinking_value, &blinking)
      || !read_optional_color(color_value, color, &color_pointer)
      || !read_optional_code(cursor_value, 5, UINT8_MAX, &cursor)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  opentui_external_cursor_style_options options = {
    .style = style,
    .blinking = blinking,
    .color = color_pointer,
    .cursor = cursor,
  };
  setCursorStyleOptions(handle, &options);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_renderer_cursor_state(value handle_value) {
  CAMLparam1(handle_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (!renderer_is_valid(handle)) {
    CAMLreturn(make_status_cursor_state(
        OPENTUI_RAW_STATUS_STALE_HANDLE,
        NULL));
  }

  opentui_external_cursor_state state;
  getCursorState(handle, &state);
  CAMLreturn(make_status_cursor_state(OPENTUI_RAW_STATUS_OK, &state));
}

static value renderer_add_to_hit_grid_impl(
    value handle_value,
    value x_value,
    value y_value,
    value width_value,
    value height_value,
    value id_value) {
  CAMLparam5(handle_value, x_value, y_value, width_value, height_value);
  CAMLxparam1(id_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  int32_t width = Int32_val(width_value);
  int32_t height = Int32_val(height_value);
  int32_t id = Int32_val(id_value);
  if (!renderer_is_valid(handle)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (width < 0 || height < 0 || id < 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  addToHitGrid(
      handle,
      Int32_val(x_value),
      Int32_val(y_value),
      (uint32_t)width,
      (uint32_t)height,
      (uint32_t)id);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_renderer_add_to_hit_grid(
    value handle_value,
    value x_value,
    value y_value,
    value width_value,
    value height_value,
    value id_value) {
  return renderer_add_to_hit_grid_impl(
      handle_value, x_value, y_value, width_value, height_value, id_value);
}

CAMLprim value opentui_raw_renderer_add_to_hit_grid_bytecode(
    value *arguments,
    int argument_count) {
  if (argument_count != 6) {
    return Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT);
  }
  return renderer_add_to_hit_grid_impl(
      arguments[0],
      arguments[1],
      arguments[2],
      arguments[3],
      arguments[4],
      arguments[5]);
}

static value renderer_add_to_hit_grid_unchecked_impl(
    value handle_value,
    value x_value,
    value y_value,
    value width_value,
    value height_value,
    value id_value) {
  CAMLparam5(handle_value, x_value, y_value, width_value, height_value);
  CAMLxparam1(id_value);

  addToHitGrid(
      (opentui_native_handle)Int32_val(handle_value),
      Int32_val(x_value),
      Int32_val(y_value),
      (uint32_t)Int32_val(width_value),
      (uint32_t)Int32_val(height_value),
      (uint32_t)Int32_val(id_value));
  CAMLreturn(Val_unit);
}

CAMLprim value opentui_raw_renderer_add_to_hit_grid_unchecked(
    value handle_value,
    value x_value,
    value y_value,
    value width_value,
    value height_value,
    value id_value) {
  return renderer_add_to_hit_grid_unchecked_impl(
      handle_value, x_value, y_value, width_value, height_value, id_value);
}

CAMLprim value opentui_raw_renderer_add_to_hit_grid_unchecked_bytecode(
    value *arguments,
    int argument_count) {
  if (argument_count != 6) {
    caml_invalid_argument("opentui_raw_renderer_add_to_hit_grid_unchecked");
  }
  return renderer_add_to_hit_grid_unchecked_impl(
      arguments[0],
      arguments[1],
      arguments[2],
      arguments[3],
      arguments[4],
      arguments[5]);
}

CAMLprim value opentui_raw_renderer_clear_current_hit_grid(value handle_value) {
  CAMLparam1(handle_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (!renderer_is_valid(handle)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }

  clearCurrentHitGrid(handle);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_renderer_clear_current_hit_grid_unchecked(
    value handle_value) {
  CAMLparam1(handle_value);

  clearCurrentHitGrid((opentui_native_handle)Int32_val(handle_value));
  CAMLreturn(Val_unit);
}

CAMLprim value opentui_raw_renderer_clear_next_hit_grid(value handle_value) {
  CAMLparam1(handle_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (!renderer_is_valid(handle)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }

  clearNextHitGrid(handle);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_renderer_clear_next_hit_grid_unchecked(
    value handle_value) {
  CAMLparam1(handle_value);

  clearNextHitGrid((opentui_native_handle)Int32_val(handle_value));
  CAMLreturn(Val_unit);
}

CAMLprim value opentui_raw_renderer_hit_grid_push_scissor_rect(
    value handle_value,
    value x_value,
    value y_value,
    value width_value,
    value height_value) {
  CAMLparam5(handle_value, x_value, y_value, width_value, height_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  int32_t width = Int32_val(width_value);
  int32_t height = Int32_val(height_value);
  if (!renderer_is_valid(handle)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (width < 0 || height < 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  hitGridPushScissorRect(
      handle,
      Int32_val(x_value),
      Int32_val(y_value),
      (uint32_t)width,
      (uint32_t)height);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_renderer_hit_grid_push_scissor_rect_unchecked(
    value handle_value,
    value x_value,
    value y_value,
    value width_value,
    value height_value) {
  CAMLparam5(handle_value, x_value, y_value, width_value, height_value);

  hitGridPushScissorRect(
      (opentui_native_handle)Int32_val(handle_value),
      Int32_val(x_value),
      Int32_val(y_value),
      (uint32_t)Int32_val(width_value),
      (uint32_t)Int32_val(height_value));
  CAMLreturn(Val_unit);
}

CAMLprim value opentui_raw_renderer_hit_grid_pop_scissor_rect(value handle_value) {
  CAMLparam1(handle_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (!renderer_is_valid(handle)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }

  hitGridPopScissorRect(handle);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_renderer_hit_grid_pop_scissor_rect_unchecked(
    value handle_value) {
  CAMLparam1(handle_value);

  hitGridPopScissorRect((opentui_native_handle)Int32_val(handle_value));
  CAMLreturn(Val_unit);
}

CAMLprim value opentui_raw_renderer_hit_grid_clear_scissor_rects(value handle_value) {
  CAMLparam1(handle_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (!renderer_is_valid(handle)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }

  hitGridClearScissorRects(handle);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_renderer_hit_grid_clear_scissor_rects_unchecked(
    value handle_value) {
  CAMLparam1(handle_value);

  hitGridClearScissorRects((opentui_native_handle)Int32_val(handle_value));
  CAMLreturn(Val_unit);
}

static value renderer_add_to_current_hit_grid_clipped_impl(
    value handle_value,
    value x_value,
    value y_value,
    value width_value,
    value height_value,
    value id_value) {
  CAMLparam5(handle_value, x_value, y_value, width_value, height_value);
  CAMLxparam1(id_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  int32_t width = Int32_val(width_value);
  int32_t height = Int32_val(height_value);
  int32_t id = Int32_val(id_value);
  if (!renderer_is_valid(handle)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (width < 0 || height < 0 || id < 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  addToCurrentHitGridClipped(
      handle,
      Int32_val(x_value),
      Int32_val(y_value),
      (uint32_t)width,
      (uint32_t)height,
      (uint32_t)id);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_renderer_add_to_current_hit_grid_clipped(
    value handle_value,
    value x_value,
    value y_value,
    value width_value,
    value height_value,
    value id_value) {
  return renderer_add_to_current_hit_grid_clipped_impl(
      handle_value, x_value, y_value, width_value, height_value, id_value);
}

CAMLprim value opentui_raw_renderer_add_to_current_hit_grid_clipped_bytecode(
    value *arguments,
    int argument_count) {
  if (argument_count != 6) {
    return Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT);
  }
  return renderer_add_to_current_hit_grid_clipped_impl(
      arguments[0],
      arguments[1],
      arguments[2],
      arguments[3],
      arguments[4],
      arguments[5]);
}

static value renderer_add_to_current_hit_grid_clipped_unchecked_impl(
    value handle_value,
    value x_value,
    value y_value,
    value width_value,
    value height_value,
    value id_value) {
  CAMLparam5(handle_value, x_value, y_value, width_value, height_value);
  CAMLxparam1(id_value);

  addToCurrentHitGridClipped(
      (opentui_native_handle)Int32_val(handle_value),
      Int32_val(x_value),
      Int32_val(y_value),
      (uint32_t)Int32_val(width_value),
      (uint32_t)Int32_val(height_value),
      (uint32_t)Int32_val(id_value));
  CAMLreturn(Val_unit);
}

CAMLprim value opentui_raw_renderer_add_to_current_hit_grid_clipped_unchecked(
    value handle_value,
    value x_value,
    value y_value,
    value width_value,
    value height_value,
    value id_value) {
  return renderer_add_to_current_hit_grid_clipped_unchecked_impl(
      handle_value, x_value, y_value, width_value, height_value, id_value);
}

CAMLprim value opentui_raw_renderer_add_to_current_hit_grid_clipped_unchecked_bytecode(
    value *arguments,
    int argument_count) {
  if (argument_count != 6) {
    caml_invalid_argument(
        "opentui_raw_renderer_add_to_current_hit_grid_clipped_unchecked");
  }
  return renderer_add_to_current_hit_grid_clipped_unchecked_impl(
      arguments[0],
      arguments[1],
      arguments[2],
      arguments[3],
      arguments[4],
      arguments[5]);
}

CAMLprim value opentui_raw_renderer_check_hit(
    value handle_value,
    value x_value,
    value y_value) {
  CAMLparam3(handle_value, x_value, y_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  int32_t x = Int32_val(x_value);
  int32_t y = Int32_val(y_value);
  if (!renderer_is_valid(handle)) {
    CAMLreturn(make_status_count(OPENTUI_RAW_STATUS_STALE_HANDLE, 0));
  }
  if (x < 0 || y < 0) {
    CAMLreturn(make_status_count(OPENTUI_RAW_STATUS_INVALID_ARGUMENT, 0));
  }

  CAMLreturn(make_status_count(
      OPENTUI_RAW_STATUS_OK,
      checkHit(handle, (uint32_t)x, (uint32_t)y)));
}

CAMLprim value opentui_raw_renderer_check_hit_unchecked(
    value handle_value,
    value x_value,
    value y_value) {
  CAMLparam3(handle_value, x_value, y_value);

  CAMLreturn(Val_int((int)checkHit(
      (opentui_native_handle)Int32_val(handle_value),
      (uint32_t)Int32_val(x_value),
      (uint32_t)Int32_val(y_value))));
}

CAMLprim value opentui_raw_renderer_get_hit_grid_dirty(value handle_value) {
  CAMLparam1(handle_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (!renderer_is_valid(handle)) {
    CAMLreturn(make_status_bool(OPENTUI_RAW_STATUS_STALE_HANDLE, false));
  }

  CAMLreturn(make_status_bool(OPENTUI_RAW_STATUS_OK, getHitGridDirty(handle)));
}

CAMLprim value opentui_raw_renderer_get_hit_grid_dirty_unchecked(
    value handle_value) {
  CAMLparam1(handle_value);

  CAMLreturn(Val_bool(getHitGridDirty(
      (opentui_native_handle)Int32_val(handle_value))));
}

CAMLprim value opentui_raw_buffer_dimensions(value handle_value) {
  CAMLparam1(handle_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (!buffer_is_valid(handle)) {
    CAMLreturn(make_status_dimensions(OPENTUI_RAW_STATUS_STALE_HANDLE, 0, 0));
  }

  CAMLreturn(make_status_dimensions(
      OPENTUI_RAW_STATUS_OK,
      getBufferWidth(handle),
      getBufferHeight(handle)));
}

CAMLprim value opentui_raw_buffer_clear(value handle_value, value color_value) {
  CAMLparam2(handle_value, color_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  uint16_t background[4];
  if (!buffer_is_valid(handle)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (!read_color(color_value, background)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  bufferClear(handle, background);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_buffer_set_cell(value handle_value, value cell_value) {
  CAMLparam2(handle_value, cell_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (!buffer_is_valid(handle)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (!Is_block(cell_value) || Wosize_val(cell_value) != 6) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  int32_t x = Int32_val(Field(cell_value, 0));
  int32_t y = Int32_val(Field(cell_value, 1));
  int32_t character = Int32_val(Field(cell_value, 2));
  uint16_t foreground[4];
  uint16_t background[4];
  if (x < 0 || y < 0
      || !read_color(Field(cell_value, 3), foreground)
      || !read_color(Field(cell_value, 4), background)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  uint32_t attributes = (uint32_t)Int32_val(Field(cell_value, 5));
  bufferSetCell(
      handle,
      (uint32_t)x,
      (uint32_t)y,
      (uint32_t)character,
      foreground,
      background,
      attributes);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_buffer_draw_text(value handle_value, value text_value) {
  CAMLparam2(handle_value, text_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (!buffer_is_valid(handle)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (!Is_block(text_value) || Wosize_val(text_value) != 6) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  value string_value = Field(text_value, 0);
  int32_t x = Int32_val(Field(text_value, 1));
  int32_t y = Int32_val(Field(text_value, 2));
  uint16_t foreground[4];
  uint16_t background[4];
  uint32_t string_length;
  if (x < 0 || y < 0
      || !read_color(Field(text_value, 3), foreground)
      || !read_color(Field(text_value, 4), background)
      || !read_text_length(string_value, &string_length)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  uint32_t attributes = (uint32_t)Int32_val(Field(text_value, 5));
  bufferDrawText(
      handle,
      (const uint8_t *)String_val(string_value),
      string_length,
      (uint32_t)x,
      (uint32_t)y,
      foreground,
      background,
      attributes);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_buffer_draw_box(value handle_value, value box_value) {
  CAMLparam2(handle_value, box_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (!buffer_is_valid(handle)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (!Is_block(box_value) || Wosize_val(box_value) != 11) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  int32_t x = Int32_val(Field(box_value, 0));
  int32_t y = Int32_val(Field(box_value, 1));
  int32_t width = Int32_val(Field(box_value, 2));
  int32_t height = Int32_val(Field(box_value, 3));
  uint32_t border_chars[11];
  uint16_t border_color[4];
  uint16_t background_color[4];
  uint16_t title_color[4];
  const uint8_t *title;
  const uint8_t *bottom_title;
  uint32_t title_length;
  uint32_t bottom_title_length;
  if (width < 0 || height < 0
      || !read_border_chars(Field(box_value, 4), border_chars)
      || !read_color(Field(box_value, 6), border_color)
      || !read_color(Field(box_value, 7), background_color)
      || !read_color(Field(box_value, 8), title_color)
      || !read_optional_text(Field(box_value, 9), &title, &title_length)
      || !read_optional_text(
             Field(box_value, 10), &bottom_title, &bottom_title_length)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  bufferDrawBox(
      handle,
      x,
      y,
      (uint32_t)width,
      (uint32_t)height,
      border_chars,
      (uint32_t)Int32_val(Field(box_value, 5)),
      border_color,
      background_color,
      title_color,
      title,
      title_length,
      bottom_title,
      bottom_title_length);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_buffer_draw_text_buffer_view(
    value buffer_handle_value,
    value view_handle_value,
    value x_value,
    value y_value) {
  CAMLparam4(buffer_handle_value, view_handle_value, x_value, y_value);

  opentui_native_handle buffer_handle =
      (opentui_native_handle)Int32_val(buffer_handle_value);
  opentui_native_handle view_handle =
      (opentui_native_handle)Int32_val(view_handle_value);
  if (!buffer_is_valid(buffer_handle) || view_handle == 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }

  bufferDrawTextBufferView(
      buffer_handle,
      view_handle,
      Int32_val(x_value),
      Int32_val(y_value));
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_buffer_write_resolved_chars(
    value handle_value,
    value output_value,
    value add_line_breaks_value) {
  CAMLparam3(handle_value, output_value, add_line_breaks_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  mlsize_t output_length = caml_string_length(output_value);
  if (!buffer_is_valid(handle)) {
    CAMLreturn(make_status_count(OPENTUI_RAW_STATUS_STALE_HANDLE, 0));
  }
  if (output_length == 0 || output_length > UINT32_MAX) {
    CAMLreturn(make_status_count(OPENTUI_RAW_STATUS_OUTPUT_TOO_SMALL, 0));
  }

  uint32_t written = bufferWriteResolvedChars(
      handle,
      (uint8_t *)Bytes_val(output_value),
      (uint32_t)output_length,
      Bool_val(add_line_breaks_value));
  if (written == 0) {
    CAMLreturn(make_status_count(OPENTUI_RAW_STATUS_OUTPUT_TOO_SMALL, 0));
  }

  CAMLreturn(make_status_count(OPENTUI_RAW_STATUS_OK, written));
}

CAMLprim value opentui_raw_optimized_buffer_create(
    value width_value,
    value height_value,
    value respect_alpha_value,
    value width_method_value,
    value id_value) {
  CAMLparam5(width_value, height_value, respect_alpha_value,
             width_method_value, id_value);

  int32_t width = Int32_val(width_value);
  int32_t height = Int32_val(height_value);
  int32_t width_method = Int32_val(width_method_value);
  uint32_t id_length;
  if (width <= 0 || height <= 0 || (width_method != 0 && width_method != 1)
      || !read_text_length(id_value, &id_length)) {
    CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_INVALID_ARGUMENT, 0));
  }

  opentui_native_handle handle = createOptimizedBuffer(
      (uint32_t)width,
      (uint32_t)height,
      Bool_val(respect_alpha_value),
      (uint8_t)width_method,
      (const uint8_t *)String_val(id_value),
      id_length);
  if (handle == 0) {
    CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_NATIVE_FAILURE, 0));
  }
  CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_OK, handle));
}

CAMLprim value opentui_raw_optimized_buffer_destroy(value handle_value) {
  CAMLparam1(handle_value);
  opentui_native_handle handle =
      (opentui_native_handle)Int32_val(handle_value);
  if (handle != 0) {
    destroyOptimizedBuffer(handle);
  }
  CAMLreturn(Val_unit);
}

CAMLprim value opentui_raw_optimized_buffer_dimensions(value handle_value) {
  CAMLparam1(handle_value);
  opentui_native_handle handle =
      (opentui_native_handle)Int32_val(handle_value);
  if (!optimized_buffer_is_valid(handle)) {
    CAMLreturn(make_status_dimensions(
        OPENTUI_RAW_STATUS_STALE_HANDLE, 0, 0));
  }
  CAMLreturn(make_status_dimensions(
      OPENTUI_RAW_STATUS_OK, getBufferWidth(handle), getBufferHeight(handle)));
}

CAMLprim value opentui_raw_optimized_buffer_clear(
    value handle_value,
    value color_value) {
  CAMLparam2(handle_value, color_value);
  opentui_native_handle handle =
      (opentui_native_handle)Int32_val(handle_value);
  uint16_t background[4];
  if (!optimized_buffer_is_valid(handle)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (!read_color(color_value, background)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }
  bufferClear(handle, background);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

static value optimized_buffer_set_cell(
    value handle_value,
    value cell_value,
    bool alpha_blending) {
  CAMLparam2(handle_value, cell_value);
  opentui_native_handle handle =
      (opentui_native_handle)Int32_val(handle_value);
  if (!optimized_buffer_is_valid(handle)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (!Is_block(cell_value) || Wosize_val(cell_value) != 6) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  int32_t x = Int32_val(Field(cell_value, 0));
  int32_t y = Int32_val(Field(cell_value, 1));
  int32_t character = Int32_val(Field(cell_value, 2));
  uint16_t foreground[4];
  uint16_t background[4];
  if (x < 0 || y < 0
      || !read_color(Field(cell_value, 3), foreground)
      || !read_color(Field(cell_value, 4), background)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  uint32_t attributes = (uint32_t)Int32_val(Field(cell_value, 5));
  if (alpha_blending) {
    bufferSetCellWithAlphaBlending(
        handle, (uint32_t)x, (uint32_t)y, (uint32_t)character,
        foreground, background, attributes);
  } else {
    bufferSetCell(
        handle, (uint32_t)x, (uint32_t)y, (uint32_t)character,
        foreground, background, attributes);
  }
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_optimized_buffer_set_cell(
    value handle_value,
    value cell_value) {
  return optimized_buffer_set_cell(handle_value, cell_value, false);
}

CAMLprim value opentui_raw_optimized_buffer_set_cell_with_alpha_blending(
    value handle_value,
    value cell_value) {
  return optimized_buffer_set_cell(handle_value, cell_value, true);
}

CAMLprim value opentui_raw_optimized_buffer_draw_text(
    value handle_value,
    value text_value) {
  CAMLparam2(handle_value, text_value);
  opentui_native_handle handle =
      (opentui_native_handle)Int32_val(handle_value);
  if (!optimized_buffer_is_valid(handle)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (!Is_block(text_value) || Wosize_val(text_value) != 6) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  value string_value = Field(text_value, 0);
  int32_t x = Int32_val(Field(text_value, 1));
  int32_t y = Int32_val(Field(text_value, 2));
  uint16_t foreground[4];
  uint16_t background[4];
  uint32_t string_length;
  if (x < 0 || y < 0
      || !read_color(Field(text_value, 3), foreground)
      || !read_color(Field(text_value, 4), background)
      || !read_text_length(string_value, &string_length)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  bufferDrawText(
      handle,
      (const uint8_t *)String_val(string_value),
      string_length,
      (uint32_t)x,
      (uint32_t)y,
      foreground,
      background,
      (uint32_t)Int32_val(Field(text_value, 5)));
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_optimized_buffer_fill_rect(
    value handle_value,
    value rect_value) {
  CAMLparam2(handle_value, rect_value);
  opentui_native_handle handle =
      (opentui_native_handle)Int32_val(handle_value);
  if (!optimized_buffer_is_valid(handle)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (!Is_block(rect_value) || Wosize_val(rect_value) != 5) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  int32_t x = Int32_val(Field(rect_value, 0));
  int32_t y = Int32_val(Field(rect_value, 1));
  int32_t width = Int32_val(Field(rect_value, 2));
  int32_t height = Int32_val(Field(rect_value, 3));
  uint16_t background[4];
  if (x < 0 || y < 0 || width < 0 || height < 0
      || !read_color(Field(rect_value, 4), background)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }
  bufferFillRect(handle, (uint32_t)x, (uint32_t)y, (uint32_t)width,
                 (uint32_t)height, background);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

static value optimized_buffer_draw_grayscale_buffer(
    value handle_value,
    value args_value,
    bool supersampled) {
  CAMLparam2(handle_value, args_value);
  opentui_native_handle handle =
      (opentui_native_handle)Int32_val(handle_value);
  if (!optimized_buffer_is_valid(handle)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (!Is_block(args_value) || Wosize_val(args_value) != 7) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  int32_t x = Int32_val(Field(args_value, 0));
  int32_t y = Int32_val(Field(args_value, 1));
  int32_t width_value = Int32_val(Field(args_value, 3));
  int32_t height_value = Int32_val(Field(args_value, 4));
  if (width_value < 0 || height_value < 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  uint32_t width = (uint32_t)width_value;
  uint32_t height = (uint32_t)height_value;
  float *intensities = NULL;
  uint16_t foreground[4];
  uint16_t background[4];
  const uint16_t *foreground_pointer;
  const uint16_t *background_pointer;
  if (!read_grayscale_floatarray(Field(args_value, 2), width, height,
                                 &intensities)
      || !read_optional_color(Field(args_value, 5), foreground,
                              &foreground_pointer)
      || !read_optional_color(Field(args_value, 6), background,
                              &background_pointer)) {
    if (intensities != NULL) caml_stat_free(intensities);
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  if (supersampled) {
    bufferDrawGrayscaleBufferSupersampled(
        handle, x, y, intensities, width, height, foreground_pointer,
        background_pointer);
  } else {
    bufferDrawGrayscaleBuffer(
        handle, x, y, intensities, width, height, foreground_pointer,
        background_pointer);
  }
  if (intensities != NULL) caml_stat_free(intensities);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_optimized_buffer_draw_grayscale_buffer(
    value handle_value,
    value args_value) {
  return optimized_buffer_draw_grayscale_buffer(handle_value, args_value, false);
}

CAMLprim value opentui_raw_optimized_buffer_draw_grayscale_buffer_supersampled(
    value handle_value,
    value args_value) {
  return optimized_buffer_draw_grayscale_buffer(handle_value, args_value, true);
}

CAMLprim value opentui_raw_optimized_buffer_draw_frame_buffer(
    value target_value,
    value args_value) {
  CAMLparam2(target_value, args_value);
  opentui_native_handle target =
      (opentui_native_handle)Int32_val(target_value);
  if (!Is_block(args_value) || Wosize_val(args_value) != 7) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }
  value x_value = Field(args_value, 0);
  value y_value = Field(args_value, 1);
  value source_value = Field(args_value, 2);
  value source_x_value = Field(args_value, 3);
  value source_y_value = Field(args_value, 4);
  value source_width_value = Field(args_value, 5);
  value source_height_value = Field(args_value, 6);
  opentui_native_handle source =
      (opentui_native_handle)Int32_val(source_value);
  int32_t x = Int32_val(x_value);
  int32_t y = Int32_val(y_value);
  int32_t source_x = Int32_val(source_x_value);
  int32_t source_y = Int32_val(source_y_value);
  int32_t source_width = Int32_val(source_width_value);
  int32_t source_height = Int32_val(source_height_value);
  if (!optimized_buffer_is_valid(target) || !optimized_buffer_is_valid(source)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (source_x < 0 || source_y < 0 || source_width < 0 || source_height < 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }
  drawFrameBuffer(target, x, y, source, (uint32_t)source_x,
                  (uint32_t)source_y, (uint32_t)source_width,
                  (uint32_t)source_height);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_optimized_buffer_resize(
    value handle_value,
    value width_value,
    value height_value) {
  CAMLparam3(handle_value, width_value, height_value);
  opentui_native_handle handle =
      (opentui_native_handle)Int32_val(handle_value);
  int32_t width = Int32_val(width_value);
  int32_t height = Int32_val(height_value);
  if (!optimized_buffer_is_valid(handle)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (width <= 0 || height <= 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }
  bufferResize(handle, (uint32_t)width, (uint32_t)height);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_optimized_buffer_draw_grid(
    value handle_value,
    value args_value) {
  CAMLparam2(handle_value, args_value);
  opentui_native_handle handle =
      (opentui_native_handle)Int32_val(handle_value);
  if (!optimized_buffer_is_valid(handle)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (!Is_block(args_value) || Wosize_val(args_value) != 7) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }
  value border_value = Field(args_value, 0);
  value foreground_value = Field(args_value, 1);
  value background_value = Field(args_value, 2);
  value columns_value = Field(args_value, 3);
  value rows_value = Field(args_value, 4);
  value draw_inner_value = Field(args_value, 5);
  value draw_outer_value = Field(args_value, 6);

  uint32_t border_chars[11];
  uint16_t foreground[4];
  uint16_t background[4];
  int32_t *columns = NULL;
  int32_t *rows = NULL;
  uint32_t column_count = 0;
  uint32_t row_count = 0;
  if (!read_border_chars(border_value, border_chars)
      || !read_color(foreground_value, foreground)
      || !read_color(background_value, background)
      || !read_int32_array(columns_value, &columns, &column_count)
      || !read_int32_array(rows_value, &rows, &row_count)) {
    if (columns != NULL) caml_stat_free(columns);
    if (rows != NULL) caml_stat_free(rows);
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  column_count = column_count == 0 ? 0 : column_count - 1;
  row_count = row_count == 0 ? 0 : row_count - 1;

  opentui_external_grid_draw_options options = {
      .draw_inner = Bool_val(draw_inner_value),
      .draw_outer = Bool_val(draw_outer_value),
  };
  bufferDrawGrid(handle, border_chars, foreground, background, columns,
                 column_count, rows, row_count, &options);
  if (columns != NULL) caml_stat_free(columns);
  if (rows != NULL) caml_stat_free(rows);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_buffer_draw_frame_buffer(
    value target_value,
    value args_value) {
  return opentui_raw_optimized_buffer_draw_frame_buffer(target_value, args_value);
}

CAMLprim value opentui_raw_buffer_draw_grid(
    value handle_value,
    value args_value) {
  return opentui_raw_optimized_buffer_draw_grid(handle_value, args_value);
}

CAMLprim value opentui_raw_buffer_set_cell_with_alpha_blending(
    value handle_value,
    value cell_value) {
  return opentui_raw_optimized_buffer_set_cell_with_alpha_blending(
      handle_value, cell_value);
}

CAMLprim value opentui_raw_buffer_fill_rect(
    value handle_value,
    value rect_value) {
  return opentui_raw_optimized_buffer_fill_rect(handle_value, rect_value);
}

CAMLprim value opentui_raw_buffer_draw_grayscale_buffer(
    value handle_value,
    value args_value) {
  return optimized_buffer_draw_grayscale_buffer(handle_value, args_value, false);
}

CAMLprim value opentui_raw_buffer_draw_grayscale_buffer_supersampled(
    value handle_value,
    value args_value) {
  return optimized_buffer_draw_grayscale_buffer(handle_value, args_value, true);
}

CAMLprim value opentui_raw_buffer_push_scissor_rect(
    value handle_value,
    value args_value) {
  CAMLparam2(handle_value, args_value);
  if (!Is_block(args_value) || Wosize_val(args_value) != 4) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }
  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  int32_t x = Int32_val(Field(args_value, 0));
  int32_t y = Int32_val(Field(args_value, 1));
  int32_t width = Int32_val(Field(args_value, 2));
  int32_t height = Int32_val(Field(args_value, 3));
  if (!buffer_is_valid(handle) || width < 0 || height < 0) {
    CAMLreturn(Val_int(
        buffer_is_valid(handle) ? OPENTUI_RAW_STATUS_INVALID_ARGUMENT
                                 : OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  bufferPushScissorRect(handle, x, y, (uint32_t)width, (uint32_t)height);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_buffer_pop_scissor_rect(value handle_value) {
  CAMLparam1(handle_value);
  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (!buffer_is_valid(handle)) CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  bufferPopScissorRect(handle);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_buffer_clear_scissor_rects(value handle_value) {
  CAMLparam1(handle_value);
  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (!buffer_is_valid(handle)) CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  bufferClearScissorRects(handle);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_buffer_push_opacity(
    value handle_value,
    value opacity_value) {
  CAMLparam2(handle_value, opacity_value);
  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (!buffer_is_valid(handle) || !Is_block(opacity_value)
      || Tag_val(opacity_value) != Double_tag
      || !isfinite(Double_val(opacity_value))) {
    CAMLreturn(Val_int(
        buffer_is_valid(handle) ? OPENTUI_RAW_STATUS_INVALID_ARGUMENT
                                 : OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  bufferPushOpacity(handle, (float)Double_val(opacity_value));
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_buffer_pop_opacity(value handle_value) {
  CAMLparam1(handle_value);
  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (!buffer_is_valid(handle)) CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  bufferPopOpacity(handle);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_buffer_get_current_opacity(value handle_value) {
  CAMLparam1(handle_value);
  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (!buffer_is_valid(handle)) CAMLreturn(caml_copy_double(1.0));
  CAMLreturn(caml_copy_double((double)bufferGetCurrentOpacity(handle)));
}

CAMLprim value opentui_raw_buffer_clear_opacity(value handle_value) {
  CAMLparam1(handle_value);
  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (!buffer_is_valid(handle)) CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  bufferClearOpacity(handle);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

#define OPENTUI_RAW_EVENT_QUEUE_CAPACITY 64
#define OPENTUI_RAW_EVENT_NAME_CAPACITY 256
#define OPENTUI_RAW_EVENT_DATA_CAPACITY 4096

typedef struct opentui_raw_event_slot {
  uint32_t name_length;
  uint32_t data_length;
  uint8_t name[OPENTUI_RAW_EVENT_NAME_CAPACITY];
  uint8_t data[OPENTUI_RAW_EVENT_DATA_CAPACITY];
} opentui_raw_event_slot;

static opentui_raw_event_slot event_queue[OPENTUI_RAW_EVENT_QUEUE_CAPACITY];
static uint32_t event_queue_head = 0;
static uint32_t event_queue_count = 0;
static bool event_queue_overflow = false;
static opentui_native_handle event_sink_handle = 0;

static void reset_event_queue(void) {
  event_queue_head = 0;
  event_queue_count = 0;
  event_queue_overflow = false;
}

static void copy_event_bytes(
    uint8_t *destination,
    uint32_t capacity,
    const uint8_t *source,
    uint32_t length) {
  if (length != 0) {
    memcpy(destination, source, length);
  }
  if (length < capacity) {
    destination[length] = 0;
  }
}

static void raw_event_callback(
    const uint8_t *name_ptr,
    uint32_t name_len,
    const uint8_t *data_ptr,
    uint32_t data_len) {
  if (event_sink_handle == 0) {
    return;
  }
  if (name_len > OPENTUI_RAW_EVENT_NAME_CAPACITY
      || data_len > OPENTUI_RAW_EVENT_DATA_CAPACITY
      || event_queue_count == OPENTUI_RAW_EVENT_QUEUE_CAPACITY) {
    event_queue_overflow = true;
    return;
  }

  uint32_t tail =
      (event_queue_head + event_queue_count) % OPENTUI_RAW_EVENT_QUEUE_CAPACITY;
  opentui_raw_event_slot *slot = &event_queue[tail];
  slot->name_length = name_len;
  slot->data_length = data_len;
  copy_event_bytes(slot->name, OPENTUI_RAW_EVENT_NAME_CAPACITY, name_ptr, name_len);
  copy_event_bytes(slot->data, OPENTUI_RAW_EVENT_DATA_CAPACITY, data_ptr, data_len);
  event_queue_count++;
}

static value make_status_event(int status, const opentui_raw_event_slot *slot) {
  CAMLparam0();
  CAMLlocal5(result, option, event, name, data);

  if (status == OPENTUI_RAW_STATUS_OK && slot != NULL) {
    name = caml_alloc_string(slot->name_length);
    data = caml_alloc_string(slot->data_length);
    if (slot->name_length != 0) {
      memcpy(Bytes_val(name), slot->name, slot->name_length);
    }
    if (slot->data_length != 0) {
      memcpy(Bytes_val(data), slot->data, slot->data_length);
    }
    event = caml_alloc_tuple(2);
    Store_field(event, 0, name);
    Store_field(event, 1, data);
    option = caml_alloc(1, 0);
    Store_field(option, 0, event);
  } else {
    option = Val_none;
  }

  result = caml_alloc_tuple(2);
  Store_field(result, 0, Val_int(status));
  Store_field(result, 1, option);
  CAMLreturn(result);
}

CAMLprim value opentui_raw_event_sink_create(value unit_value) {
  CAMLparam1(unit_value);

  if (event_sink_handle != 0) {
    CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_INVALID_ARGUMENT, 0));
  }

  reset_event_queue();
  opentui_native_handle handle = createEventSink(raw_event_callback);
  if (handle == 0) {
    CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_NATIVE_FAILURE, 0));
  }

  event_sink_handle = handle;
  CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_OK, handle));
}

CAMLprim value opentui_raw_event_sink_destroy(value handle_value) {
  CAMLparam1(handle_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (handle != 0 && handle == event_sink_handle) {
    destroyEventSink(handle);
    event_sink_handle = 0;
    reset_event_queue();
  }

  CAMLreturn(Val_unit);
}

CAMLprim value opentui_raw_event_sink_poll(value handle_value) {
  CAMLparam1(handle_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (handle == 0 || handle != event_sink_handle) {
    CAMLreturn(make_status_event(OPENTUI_RAW_STATUS_STALE_HANDLE, NULL));
  }
  if (event_queue_count == 0 && event_queue_overflow) {
    event_queue_overflow = false;
    CAMLreturn(make_status_event(OPENTUI_RAW_STATUS_QUEUE_OVERFLOW, NULL));
  }
  if (event_queue_count == 0) {
    CAMLreturn(make_status_event(OPENTUI_RAW_STATUS_OK, NULL));
  }

  const opentui_raw_event_slot *slot = &event_queue[event_queue_head];
  value result = make_status_event(OPENTUI_RAW_STATUS_OK, slot);
  event_queue_head = (event_queue_head + 1) % OPENTUI_RAW_EVENT_QUEUE_CAPACITY;
  event_queue_count--;
  CAMLreturn(result);
}

/* Test-only producer for the typed queue; the edit-buffer API is not exposed by this package. */
CAMLprim value opentui_raw_test_event_sink_emit(value unit_value) {
  CAMLparam1(unit_value);

  if (event_sink_handle == 0) {
    CAMLreturn(Val_false);
  }

  opentui_native_handle edit_buffer = createEditBuffer(1, event_sink_handle);
  if (edit_buffer == 0) {
    CAMLreturn(Val_false);
  }

  static const uint8_t text[] = {'X'};
  editBufferInsertText(edit_buffer, text, sizeof(text));
  destroyEditBuffer(edit_buffer);
  CAMLreturn(Val_true);
}
