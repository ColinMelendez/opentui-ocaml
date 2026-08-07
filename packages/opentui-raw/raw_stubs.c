#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#include "native/opentui_abi.h"
#include "raw_status.h"

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

static bool buffer_is_valid(opentui_native_handle handle) {
  return handle != 0 && getBufferWidth(handle) != 0;
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

static bool read_text_length(value text, uint32_t *length) {
  mlsize_t text_length = caml_string_length(text);
  if (text_length > UINT32_MAX) {
    return false;
  }

  *length = (uint32_t)text_length;
  return true;
}

CAMLprim value opentui_raw_renderer_create(value width_value, value height_value) {
  CAMLparam2(width_value, height_value);

  int32_t width = Int32_val(width_value);
  int32_t height = Int32_val(height_value);
  if (width <= 0 || height <= 0) {
    CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_INVALID_ARGUMENT, 0));
  }

  opentui_native_handle handle =
      createRenderer((uint32_t)width, (uint32_t)height, 1, 2, NULL);
  if (handle == 0) {
    CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_NATIVE_FAILURE, 0));
  }

  setUseThread(handle, false);
  CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_OK, handle));
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
