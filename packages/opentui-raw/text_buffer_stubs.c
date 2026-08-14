#include <caml/alloc.h>
#include <caml/bigarray.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#include <stdint.h>

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

static value make_status_int32(int status, int32_t result_value) {
  CAMLparam0();
  CAMLlocal3(result, status_value, value_value);

  status_value = Val_int(status);
  value_value = caml_copy_int32(result_value);
  result = caml_alloc_tuple(2);
  Store_field(result, 0, status_value);
  Store_field(result, 1, value_value);
  CAMLreturn(result);
}

static value make_status_measure(
    int status,
    uint32_t line_count,
    uint32_t width_cols_max) {
  CAMLparam0();
  CAMLlocal4(result, status_value, line_count_value, width_value);

  status_value = Val_int(status);
  line_count_value = caml_copy_int32((int32_t)line_count);
  width_value = caml_copy_int32((int32_t)width_cols_max);
  result = caml_alloc_tuple(3);
  Store_field(result, 0, status_value);
  Store_field(result, 1, line_count_value);
  Store_field(result, 2, width_value);
  CAMLreturn(result);
}

static bool read_byte_array(
    value array_value,
    const uint8_t **data,
    uint32_t *length) {
  struct caml_ba_array *array = Caml_ba_array_val(array_value);
  if (array->num_dims != 1 || array->dim[0] < 0
      || (uintnat)array->dim[0] > UINT32_MAX) {
    return false;
  }

  *length = (uint32_t)array->dim[0];
  *data = *length == 0 ? NULL : (const uint8_t *)Caml_ba_data_val(array_value);
  return true;
}

static int read_byte_array_status(
    value array_value,
    const uint8_t **data,
    uint32_t *length) {
  if (!read_byte_array(array_value, data, length)) {
    return OPENTUI_RAW_STATUS_INVALID_ARGUMENT;
  }
  return OPENTUI_RAW_STATUS_OK;
}

CAMLprim value opentui_raw_text_buffer_create(value width_method_value) {
  CAMLparam1(width_method_value);

  int32_t width_method = Int32_val(width_method_value);
  if (width_method < 0 || width_method > 1) {
    CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_INVALID_ARGUMENT, 0));
  }

  opentui_native_handle handle = createTextBuffer((uint8_t)width_method);
  if (handle == 0) {
    CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_NATIVE_FAILURE, 0));
  }

  CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_OK, handle));
}

CAMLprim value opentui_raw_text_buffer_destroy(value handle_value) {
  CAMLparam1(handle_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (handle != 0) {
    destroyTextBuffer(handle);
  }

  CAMLreturn(Val_unit);
}

CAMLprim value opentui_raw_text_buffer_clear(value handle_value) {
  CAMLparam1(handle_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (handle == 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }

  textBufferClear(handle);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_text_buffer_append(
    value handle_value,
    value array_value) {
  CAMLparam2(handle_value, array_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (handle == 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }

  const uint8_t *data;
  uint32_t length;
  if (!read_byte_array(array_value, &data, &length)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  uint32_t before = textBufferGetByteSize(handle);
  textBufferAppend(handle, data, length);
  uint32_t after = textBufferGetByteSize(handle);
  if (length != 0 && after == before) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_NATIVE_FAILURE));
  }

  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_text_buffer_register_mem_buffer(
    value handle_value,
    value array_value,
    value owned_value) {
  CAMLparam3(handle_value, array_value, owned_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (handle == 0) {
    CAMLreturn(make_status_int32(OPENTUI_RAW_STATUS_STALE_HANDLE, -1));
  }

  const uint8_t *data;
  uint32_t length;
  int read_status = read_byte_array_status(array_value, &data, &length);
  if (read_status != OPENTUI_RAW_STATUS_OK) {
    CAMLreturn(make_status_int32(read_status, -1));
  }

  uint16_t mem_id = textBufferRegisterMemBuffer(
      handle, data, length, Bool_val(owned_value));
  if (mem_id == UINT16_MAX) {
    CAMLreturn(make_status_int32(OPENTUI_RAW_STATUS_NATIVE_FAILURE, -1));
  }

  CAMLreturn(make_status_int32(OPENTUI_RAW_STATUS_OK, (int32_t)mem_id));
}

CAMLprim value opentui_raw_text_buffer_replace_mem_buffer(
    value handle_value,
    value mem_id_value,
    value array_value,
    value owned_value) {
  CAMLparam4(handle_value, mem_id_value, array_value, owned_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  int32_t mem_id = Int32_val(mem_id_value);
  if (handle == 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (mem_id < 0 || mem_id > UINT8_MAX) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  const uint8_t *data;
  uint32_t length;
  int read_status = read_byte_array_status(array_value, &data, &length);
  if (read_status != OPENTUI_RAW_STATUS_OK) {
    CAMLreturn(Val_int(read_status));
  }

  if (!textBufferReplaceMemBuffer(
          handle, (uint8_t)mem_id, data, length, Bool_val(owned_value))) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_NATIVE_FAILURE));
  }

  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_text_buffer_set_text_from_mem(
    value handle_value,
    value mem_id_value,
    value expected_byte_size_value) {
  CAMLparam3(handle_value, mem_id_value, expected_byte_size_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  int32_t mem_id = Int32_val(mem_id_value);
  if (handle == 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (mem_id < 0 || mem_id > UINT8_MAX) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  uint32_t expected_byte_size =
      (uint32_t)Int32_val(expected_byte_size_value);
  textBufferSetTextFromMem(handle, (uint8_t)mem_id);
  if (textBufferGetByteSize(handle) != expected_byte_size) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_NATIVE_FAILURE));
  }

  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_text_buffer_length(value handle_value) {
  CAMLparam1(handle_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (handle == 0) {
    CAMLreturn(make_status_int32(OPENTUI_RAW_STATUS_STALE_HANDLE, 0));
  }

  CAMLreturn(make_status_int32(
      OPENTUI_RAW_STATUS_OK,
      (int32_t)textBufferGetLength(handle)));
}

CAMLprim value opentui_raw_text_buffer_byte_size(value handle_value) {
  CAMLparam1(handle_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (handle == 0) {
    CAMLreturn(make_status_int32(OPENTUI_RAW_STATUS_STALE_HANDLE, 0));
  }

  CAMLreturn(make_status_int32(
      OPENTUI_RAW_STATUS_OK,
      (int32_t)textBufferGetByteSize(handle)));
}

CAMLprim value opentui_raw_text_buffer_view_create(value buffer_value) {
  CAMLparam1(buffer_value);

  opentui_native_handle buffer =
      (opentui_native_handle)Int32_val(buffer_value);
  if (buffer == 0) {
    CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_STALE_HANDLE, 0));
  }

  opentui_native_handle handle = createTextBufferView(buffer);
  if (handle == 0) {
    CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_NATIVE_FAILURE, 0));
  }

  CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_OK, handle));
}

CAMLprim value opentui_raw_text_buffer_view_destroy(value handle_value) {
  CAMLparam1(handle_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (handle != 0) {
    destroyTextBufferView(handle);
  }

  CAMLreturn(Val_unit);
}

CAMLprim value opentui_raw_text_buffer_view_set_wrap_width(
    value handle_value,
    value width_value) {
  CAMLparam2(handle_value, width_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  int32_t width = Int32_val(width_value);
  if (handle == 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (width < 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  textBufferViewSetWrapWidth(handle, (uint32_t)width);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_text_buffer_view_set_wrap_mode(
    value handle_value,
    value mode_value) {
  CAMLparam2(handle_value, mode_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  int32_t mode = Int32_val(mode_value);
  if (handle == 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (mode < 0 || mode > 2) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  textBufferViewSetWrapMode(handle, (uint8_t)mode);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_text_buffer_view_set_first_line_offset(
    value handle_value,
    value offset_value) {
  CAMLparam2(handle_value, offset_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  int32_t offset = Int32_val(offset_value);
  if (handle == 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (offset < 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  textBufferViewSetFirstLineOffset(handle, (uint32_t)offset);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_text_buffer_view_measure_for_dimensions(
    value handle_value,
    value width_value,
    value height_value) {
  CAMLparam3(handle_value, width_value, height_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  int32_t width = Int32_val(width_value);
  int32_t height = Int32_val(height_value);
  if (handle == 0) {
    CAMLreturn(make_status_measure(OPENTUI_RAW_STATUS_STALE_HANDLE, 0, 0));
  }
  if (width < 0 || height < 0) {
    CAMLreturn(make_status_measure(OPENTUI_RAW_STATUS_INVALID_ARGUMENT, 0, 0));
  }

  opentui_external_measure_result result;
  if (!textBufferViewMeasureForDimensions(
          handle,
          (uint32_t)width,
          (uint32_t)height,
          &result)) {
    CAMLreturn(make_status_measure(OPENTUI_RAW_STATUS_NATIVE_FAILURE, 0, 0));
  }

  CAMLreturn(make_status_measure(
      OPENTUI_RAW_STATUS_OK,
      result.line_count,
      result.width_cols_max));
}

CAMLprim value opentui_raw_native_renderable_create(value unit_value) {
  CAMLparam1(unit_value);

  opentui_native_handle handle = createNativeRenderable();
  if (handle == 0) {
    CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_NATIVE_FAILURE, 0));
  }

  CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_OK, handle));
}

CAMLprim value opentui_raw_native_renderable_destroy(value handle_value) {
  CAMLparam1(handle_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (handle != 0) {
    destroyNativeRenderable(handle);
  }

  CAMLreturn(Val_unit);
}

CAMLprim value opentui_raw_native_renderable_set_measure_target(
    value renderable_value,
    value kind_value,
    value target_value) {
  CAMLparam3(renderable_value, kind_value, target_value);

  opentui_native_handle renderable =
      (opentui_native_handle)Int32_val(renderable_value);
  uint32_t kind = (uint32_t)Int32_val(kind_value);
  opentui_native_handle target = (opentui_native_handle)Int32_val(target_value);
  if (renderable == 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (kind == 0 && target != 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }
  if (kind == 1 && target == 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }
  if (kind > 1) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }
  if (!nativeRenderableSetMeasureTarget(renderable, kind, target)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_NATIVE_FAILURE));
  }

  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_native_renderable_clear_measure_target(
    value renderable_value) {
  CAMLparam1(renderable_value);

  opentui_native_handle renderable =
      (opentui_native_handle)Int32_val(renderable_value);
  if (renderable == 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (!nativeRenderableSetMeasureTarget(renderable, 0, 0)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_NATIVE_FAILURE));
  }

  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}
