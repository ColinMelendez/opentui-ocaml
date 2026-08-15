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

static value copy_u32_array(const uint32_t *pointer, uint32_t length) {
  CAMLparam0();
  CAMLlocal1(result);

  result = caml_alloc(length, 0);
  for (uint32_t index = 0; index < length; index++) {
    Store_field(result, index, caml_copy_int32((int32_t)pointer[index]));
  }
  CAMLreturn(result);
}

static value make_status_line_info(
    int status,
    const opentui_external_line_info *line_info) {
  CAMLparam0();
  CAMLlocal5(result, starts_value, widths_value, sources_value, wraps_value);

  if (line_info == NULL) {
    starts_value = caml_alloc(0, 0);
    widths_value = caml_alloc(0, 0);
    sources_value = caml_alloc(0, 0);
    wraps_value = caml_alloc(0, 0);
  } else {
    starts_value = copy_u32_array(line_info->start_cols_ptr,
        line_info->start_cols_len);
    widths_value = copy_u32_array(line_info->width_cols_ptr,
        line_info->width_cols_len);
    sources_value = copy_u32_array(line_info->sources_ptr,
        line_info->sources_len);
    wraps_value = copy_u32_array(line_info->wraps_ptr,
        line_info->wraps_len);
  }
  result = caml_alloc_tuple(6);
  Store_field(result, 0, Val_int(status));
  Store_field(result, 1, starts_value);
  Store_field(result, 2, widths_value);
  Store_field(result, 3, sources_value);
  Store_field(result, 4, wraps_value);
  Store_field(result, 5,
      caml_copy_int32(line_info == NULL ? 0 : (int32_t)line_info->width_cols_max));
  CAMLreturn(result);
}

static value make_status_bool(int status, bool result_value) {
  CAMLparam0();
  CAMLlocal3(result, status_value, bool_value);

  status_value = Val_int(status);
  bool_value = Val_bool(result_value);
  result = caml_alloc_tuple(2);
  Store_field(result, 0, status_value);
  Store_field(result, 1, bool_value);
  CAMLreturn(result);
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

static bool read_optional_color(
    value color_option,
    uint16_t output[4],
    const uint16_t **pointer) {
  if (color_option == Val_none) {
    *pointer = NULL;
    return true;
  }
  if (!Is_block(color_option) || Wosize_val(color_option) != 1
      || !read_color(Field(color_option, 0), output)) {
    return false;
  }
  *pointer = output;
  return true;
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

CAMLprim value opentui_raw_text_buffer_reset(value handle_value) {
  CAMLparam1(handle_value);
  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (handle == 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  textBufferReset(handle);
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

CAMLprim value opentui_raw_text_buffer_line_count(value handle_value) {
  CAMLparam1(handle_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (handle == 0) {
    CAMLreturn(make_status_int32(OPENTUI_RAW_STATUS_STALE_HANDLE, 0));
  }

  CAMLreturn(make_status_int32(
      OPENTUI_RAW_STATUS_OK,
      (int32_t)textBufferGetLineCount(handle)));
}

CAMLprim value opentui_raw_text_buffer_load_file(
    value handle_value,
    value path_value) {
  CAMLparam2(handle_value, path_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (handle == 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (!Is_block(path_value) || Tag_val(path_value) != String_tag) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  size_t path_length = caml_string_length(path_value);
  if (path_length > UINT32_MAX) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  bool loaded = textBufferLoadFile(
      handle,
      (const uint8_t *)String_val(path_value),
      (uint32_t)path_length);
  CAMLreturn(Val_int(
      loaded ? OPENTUI_RAW_STATUS_OK : OPENTUI_RAW_STATUS_NATIVE_FAILURE));
}

CAMLprim value opentui_raw_text_buffer_get_tab_width(value handle_value) {
  CAMLparam1(handle_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (handle == 0) {
    CAMLreturn(make_status_int32(OPENTUI_RAW_STATUS_STALE_HANDLE, 0));
  }

  CAMLreturn(make_status_int32(
      OPENTUI_RAW_STATUS_OK,
      (int32_t)textBufferGetTabWidth(handle)));
}

CAMLprim value opentui_raw_text_buffer_set_tab_width(
    value handle_value,
    value width_value) {
  CAMLparam2(handle_value, width_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  int32_t width = Int32_val(width_value);
  if (handle == 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (width < 0 || width > UINT8_MAX) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  textBufferSetTabWidth(handle, (uint8_t)width);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

static bool is_string_value(value value_to_check) {
  return Is_block(value_to_check) && Tag_val(value_to_check) == String_tag;
}

static bool is_option_string(
    value option_value,
    const uint8_t **pointer,
    size_t *length) {
  if (option_value == Val_none) {
    *pointer = NULL;
    *length = 0;
    return true;
  }
  if (!Is_block(option_value) || Wosize_val(option_value) != 1
      || !is_string_value(Field(option_value, 0))) {
    return false;
  }
  value string_value = Field(option_value, 0);
  *pointer = (const uint8_t *)String_val(string_value);
  *length = caml_string_length(string_value);
  return true;
}

static bool read_styled_chunks(
    value list_value,
    opentui_external_styled_chunk **chunks_output,
    uint32_t *count_output,
    uint16_t **fg_values_output,
    uint16_t **bg_values_output) {
  uint64_t count = 0;
  value cursor = list_value;
  while (cursor != Val_emptylist) {
    if (!Is_block(cursor) || Tag_val(cursor) != 0 || Wosize_val(cursor) != 2) {
      return false;
    }
    count++;
    if (count > UINT32_MAX) {
      return false;
    }
    cursor = Field(cursor, 1);
  }

  *chunks_output = NULL;
  *fg_values_output = NULL;
  *bg_values_output = NULL;
  *count_output = (uint32_t)count;
  if (count == 0) {
    return true;
  }
  *chunks_output = (opentui_external_styled_chunk *)caml_stat_alloc(
      sizeof(opentui_external_styled_chunk) * (size_t)count);
  *fg_values_output = (uint16_t *)caml_stat_alloc(
      sizeof(uint16_t) * 4 * (size_t)count);
  *bg_values_output = (uint16_t *)caml_stat_alloc(
      sizeof(uint16_t) * 4 * (size_t)count);

  cursor = list_value;
  for (uint32_t index = 0; index < (uint32_t)count; index++) {
    value pair = Field(cursor, 0);
    if (!Is_block(pair) || Tag_val(pair) != 0 || Wosize_val(pair) != 5) {
      caml_stat_free(*chunks_output);
      caml_stat_free(*fg_values_output);
      caml_stat_free(*bg_values_output);
      *chunks_output = NULL;
      *fg_values_output = NULL;
      *bg_values_output = NULL;
      return false;
    }
    value text_value = Field(pair, 0);
    if (!is_string_value(text_value)) {
      caml_stat_free(*chunks_output);
      caml_stat_free(*fg_values_output);
      caml_stat_free(*bg_values_output);
      *chunks_output = NULL;
      *fg_values_output = NULL;
      *bg_values_output = NULL;
      return false;
    }
    const uint16_t *fg_pointer;
    const uint16_t *bg_pointer;
    if (!read_optional_color(Field(pair, 1), *fg_values_output + index * 4,
            &fg_pointer)
        || !read_optional_color(Field(pair, 2), *bg_values_output + index * 4,
            &bg_pointer)
        || !Is_block(Field(pair, 3))) {
      caml_stat_free(*chunks_output);
      caml_stat_free(*fg_values_output);
      caml_stat_free(*bg_values_output);
      *chunks_output = NULL;
      *fg_values_output = NULL;
      *bg_values_output = NULL;
      return false;
    }
    const uint8_t *link_pointer;
    size_t link_length;
    if (!is_option_string(Field(pair, 4), &link_pointer, &link_length)) {
      caml_stat_free(*chunks_output);
      caml_stat_free(*fg_values_output);
      caml_stat_free(*bg_values_output);
      *chunks_output = NULL;
      *fg_values_output = NULL;
      *bg_values_output = NULL;
      return false;
    }
    (*chunks_output)[index].text_ptr = (const uint8_t *)String_val(text_value);
    (*chunks_output)[index].text_len = caml_string_length(text_value);
    (*chunks_output)[index].fg_ptr = fg_pointer;
    (*chunks_output)[index].bg_ptr = bg_pointer;
    (*chunks_output)[index].attributes = (uint32_t)Int32_val(Field(pair, 3));
    (*chunks_output)[index].link_ptr = link_pointer;
    (*chunks_output)[index].link_len = link_length;
    cursor = Field(cursor, 1);
  }
  return true;
}

CAMLprim value opentui_raw_text_buffer_set_styled_text(
    value handle_value,
    value chunks_value) {
  CAMLparam2(handle_value, chunks_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (handle == 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (chunks_value == Val_emptylist) {
    textBufferClear(handle);
    textBufferClearAllHighlights(handle);
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
  }
  opentui_external_styled_chunk *chunks;
  uint16_t *fg_values;
  uint16_t *bg_values;
  uint32_t count;
  if (!read_styled_chunks(chunks_value, &chunks, &count, &fg_values,
          &bg_values)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }
  textBufferSetStyledText(handle, chunks, count);
  caml_stat_free(chunks);
  caml_stat_free(fg_values);
  caml_stat_free(bg_values);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_text_buffer_clear_all_highlights(value handle_value) {
  CAMLparam1(handle_value);
  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (handle == 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  textBufferClearAllHighlights(handle);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

static bool read_highlight(value highlight_value,
    opentui_external_highlight *highlight) {
  if (!Is_block(highlight_value) || Wosize_val(highlight_value) != 5) {
    return false;
  }
  if (!Is_long(Field(highlight_value, 3))
      || !Is_long(Field(highlight_value, 4))) {
    return false;
  }
  int priority = Long_val(Field(highlight_value, 3));
  int hl_ref = Long_val(Field(highlight_value, 4));
  if (priority < 0 || priority > UINT8_MAX || hl_ref < 0 || hl_ref > UINT16_MAX) {
    return false;
  }
  highlight->start = (uint32_t)Int32_val(Field(highlight_value, 0));
  highlight->end = (uint32_t)Int32_val(Field(highlight_value, 1));
  highlight->style_id = (uint32_t)Int32_val(Field(highlight_value, 2));
  highlight->priority = (uint8_t)priority;
  highlight->hl_ref = (uint16_t)hl_ref;
  return true;
}

CAMLprim value opentui_raw_text_buffer_add_highlight_by_char_range(
    value handle_value, value highlight_value) {
  CAMLparam2(handle_value, highlight_value);
  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  opentui_external_highlight highlight;
  if (handle == 0) CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  if (!read_highlight(highlight_value, &highlight)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }
  textBufferAddHighlightByCharRange(handle, &highlight);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_text_buffer_add_highlight(
    value handle_value, value line_value, value highlight_value) {
  CAMLparam3(handle_value, line_value, highlight_value);
  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  opentui_external_highlight highlight;
  if (handle == 0) CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  if (!Is_block(line_value) || Tag_val(line_value) != Custom_tag
      || !read_highlight(highlight_value, &highlight)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }
  int32_t line = Int32_val(line_value);
  if (line < 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }
  textBufferAddHighlight(handle, (uint32_t)line, &highlight);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_text_buffer_remove_highlights_by_ref(
    value handle_value, value reference_value) {
  CAMLparam2(handle_value, reference_value);
  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (handle == 0) CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  if (!Is_long(reference_value) || Long_val(reference_value) < 0
      || Long_val(reference_value) > UINT16_MAX) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }
  textBufferRemoveHighlightsByRef(handle, (uint16_t)Long_val(reference_value));
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_text_buffer_clear_line_highlights(
    value handle_value, value line_value) {
  CAMLparam2(handle_value, line_value);
  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (handle == 0) CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  if (!Is_block(line_value) || Tag_val(line_value) != Custom_tag) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }
  int32_t line = Int32_val(line_value);
  if (line < 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }
  textBufferClearLineHighlights(handle, (uint32_t)line);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_text_buffer_set_default_fg(
    value handle_value,
    value color_value) {
  CAMLparam2(handle_value, color_value);
  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  uint16_t color[4];
  const uint16_t *pointer;
  if (handle == 0) CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  if (!read_optional_color(color_value, color, &pointer)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }
  textBufferSetDefaultFg(handle, pointer);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_text_buffer_set_default_bg(
    value handle_value,
    value color_value) {
  CAMLparam2(handle_value, color_value);
  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  uint16_t color[4];
  const uint16_t *pointer;
  if (handle == 0) CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  if (!read_optional_color(color_value, color, &pointer)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }
  textBufferSetDefaultBg(handle, pointer);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_text_buffer_set_default_attributes(
    value handle_value,
    value attributes_value) {
  CAMLparam2(handle_value, attributes_value);
  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  uint32_t attributes;
  const uint32_t *pointer = NULL;
  if (handle == 0) CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  if (attributes_value != Val_none) {
    if (!Is_block(attributes_value) || Wosize_val(attributes_value) != 1
        || !Is_block(Field(attributes_value, 0))) {
      CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
    }
    attributes = (uint32_t)Int32_val(Field(attributes_value, 0));
    pointer = &attributes;
  }
  textBufferSetDefaultAttributes(handle, pointer);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_text_buffer_reset_defaults(value handle_value) {
  CAMLparam1(handle_value);
  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (handle == 0) CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  textBufferResetDefaults(handle);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_text_buffer_set_syntax_style(
    value handle_value,
    value style_value) {
  CAMLparam2(handle_value, style_value);
  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  opentui_native_handle style = style_value == Val_none
      ? 0
      : (opentui_native_handle)Int32_val(Field(style_value, 0));
  if (handle == 0) CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  if (style_value != Val_none
      && (!Is_block(style_value) || Wosize_val(style_value) != 1)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }
  if (!textBufferSetSyntaxStyle(handle, style)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_NATIVE_FAILURE));
  }
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
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

CAMLprim value opentui_raw_text_buffer_view_set_selection(
    value handle_value,
    value start_value,
    value end_value,
    value background_value,
    value foreground_value) {
  CAMLparam5(handle_value, start_value, end_value, background_value,
      foreground_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  int32_t start = Int32_val(start_value);
  int32_t end = Int32_val(end_value);
  uint16_t background[4];
  uint16_t foreground[4];
  const uint16_t *background_ptr;
  const uint16_t *foreground_ptr;
  if (handle == 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (start < 0 || end < 0
      || !read_optional_color(background_value, background, &background_ptr)
      || !read_optional_color(foreground_value, foreground, &foreground_ptr)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  textBufferViewSetSelection(handle, (uint32_t)start, (uint32_t)end,
      background_ptr, foreground_ptr);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_text_buffer_view_update_selection(
    value handle_value,
    value end_value,
    value background_value,
    value foreground_value) {
  CAMLparam4(handle_value, end_value, background_value, foreground_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  int32_t end = Int32_val(end_value);
  uint16_t background[4];
  uint16_t foreground[4];
  const uint16_t *background_ptr;
  const uint16_t *foreground_ptr;
  if (handle == 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (end < 0
      || !read_optional_color(background_value, background, &background_ptr)
      || !read_optional_color(foreground_value, foreground, &foreground_ptr)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  textBufferViewUpdateSelection(handle, (uint32_t)end, background_ptr,
      foreground_ptr);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_text_buffer_view_reset_selection(value handle_value) {
  CAMLparam1(handle_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (handle == 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  textBufferViewResetSelection(handle);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_text_buffer_view_get_selection_info(value handle_value) {
  CAMLparam1(handle_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  uint64_t selection = handle == 0
      ? UINT64_MAX
      : textBufferViewGetSelectionInfo(handle);
  CAMLreturn(caml_copy_int64((int64_t)selection));
}

static int local_selection_arguments(
    value handle_value,
    value coordinates_value,
    opentui_native_handle *handle,
    int32_t *anchor_x,
    int32_t *anchor_y,
    int32_t *focus_x,
    int32_t *focus_y,
    uint16_t background[4],
    uint16_t foreground[4],
    const uint16_t **background_ptr,
    const uint16_t **foreground_ptr) {
  if (!Is_block(coordinates_value) || Wosize_val(coordinates_value) != 6) {
    return OPENTUI_RAW_STATUS_INVALID_ARGUMENT;
  }
  value anchor_x_value = Field(coordinates_value, 0);
  value anchor_y_value = Field(coordinates_value, 1);
  value focus_x_value = Field(coordinates_value, 2);
  value focus_y_value = Field(coordinates_value, 3);
  value background_value = Field(coordinates_value, 4);
  value foreground_value = Field(coordinates_value, 5);
  *handle = (opentui_native_handle)Int32_val(handle_value);
  *anchor_x = Int32_val(anchor_x_value);
  *anchor_y = Int32_val(anchor_y_value);
  *focus_x = Int32_val(focus_x_value);
  *focus_y = Int32_val(focus_y_value);
  if (*handle == 0) {
    return OPENTUI_RAW_STATUS_STALE_HANDLE;
  }
  if (!read_optional_color(background_value, background, background_ptr)
      || !read_optional_color(foreground_value, foreground, foreground_ptr)) {
    return OPENTUI_RAW_STATUS_INVALID_ARGUMENT;
  }
  return OPENTUI_RAW_STATUS_OK;
}

CAMLprim value opentui_raw_text_buffer_view_set_local_selection(
    value handle_value,
    value coordinates_value) {
  CAMLparam2(handle_value, coordinates_value);

  opentui_native_handle handle;
  int32_t anchor_x;
  int32_t anchor_y;
  int32_t focus_x;
  int32_t focus_y;
  uint16_t background[4];
  uint16_t foreground[4];
  const uint16_t *background_ptr;
  const uint16_t *foreground_ptr;
  int status = local_selection_arguments(handle_value, coordinates_value,
      &handle, &anchor_x, &anchor_y, &focus_x, &focus_y, background, foreground,
      &background_ptr, &foreground_ptr);
  if (status != OPENTUI_RAW_STATUS_OK) {
    CAMLreturn(make_status_bool(status, false));
  }
  CAMLreturn(make_status_bool(status,
      textBufferViewSetLocalSelection(handle, anchor_x, anchor_y, focus_x,
          focus_y, background_ptr, foreground_ptr)));
}

CAMLprim value opentui_raw_text_buffer_view_update_local_selection(
    value handle_value,
    value coordinates_value) {
  CAMLparam2(handle_value, coordinates_value);

  opentui_native_handle handle;
  int32_t anchor_x;
  int32_t anchor_y;
  int32_t focus_x;
  int32_t focus_y;
  uint16_t background[4];
  uint16_t foreground[4];
  const uint16_t *background_ptr;
  const uint16_t *foreground_ptr;
  int status = local_selection_arguments(handle_value, coordinates_value,
      &handle, &anchor_x, &anchor_y, &focus_x, &focus_y, background, foreground,
      &background_ptr, &foreground_ptr);
  if (status != OPENTUI_RAW_STATUS_OK) {
    CAMLreturn(make_status_bool(status, false));
  }
  CAMLreturn(make_status_bool(status,
      textBufferViewUpdateLocalSelection(handle, anchor_x, anchor_y, focus_x,
          focus_y, background_ptr, foreground_ptr)));
}

CAMLprim value opentui_raw_text_buffer_view_reset_local_selection(
    value handle_value) {
  CAMLparam1(handle_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (handle == 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  textBufferViewResetLocalSelection(handle);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_text_buffer_view_get_selected_text(
    value handle_value,
    value output_value,
    value length_value) {
  CAMLparam3(handle_value, output_value, length_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  int32_t length = Int32_val(length_value);
  mlsize_t output_length = caml_string_length(output_value);
  if (handle == 0) {
    CAMLreturn(make_status_int32(OPENTUI_RAW_STATUS_STALE_HANDLE, 0));
  }
  if (length < 0 || (uint64_t)length > output_length) {
    CAMLreturn(make_status_int32(OPENTUI_RAW_STATUS_INVALID_ARGUMENT, 0));
  }
  uint32_t copied = textBufferViewGetSelectedText(handle,
      (uint8_t *)Bytes_val(output_value), (uint32_t)length);
  CAMLreturn(make_status_int32(OPENTUI_RAW_STATUS_OK, (int32_t)copied));
}

CAMLprim value opentui_raw_text_buffer_view_set_viewport_size(
    value handle_value, value width_value, value height_value) {
  CAMLparam3(handle_value, width_value, height_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  int32_t width = Int32_val(width_value);
  int32_t height = Int32_val(height_value);
  if (handle == 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (width < 0 || height < 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }
  textBufferViewSetViewportSize(handle, (uint32_t)width, (uint32_t)height);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_text_buffer_view_set_viewport(
    value handle_value, value x_value, value y_value, value width_value,
    value height_value) {
  CAMLparam5(handle_value, x_value, y_value, width_value, height_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  int32_t x = Int32_val(x_value);
  int32_t y = Int32_val(y_value);
  int32_t width = Int32_val(width_value);
  int32_t height = Int32_val(height_value);
  if (handle == 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (x < 0 || y < 0 || width < 0 || height < 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }
  textBufferViewSetViewport(handle, (uint32_t)x, (uint32_t)y,
      (uint32_t)width, (uint32_t)height);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_text_buffer_view_get_virtual_line_count(
    value handle_value) {
  CAMLparam1(handle_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (handle == 0) {
    CAMLreturn(make_status_int32(OPENTUI_RAW_STATUS_STALE_HANDLE, 0));
  }
  CAMLreturn(make_status_int32(OPENTUI_RAW_STATUS_OK,
      (int32_t)textBufferViewGetVirtualLineCount(handle)));
}

CAMLprim value opentui_raw_text_buffer_view_set_tab_indicator(
    value handle_value, value indicator_value) {
  CAMLparam2(handle_value, indicator_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  int32_t indicator = Int32_val(indicator_value);
  if (handle == 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (indicator < 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }
  textBufferViewSetTabIndicator(handle, (uint32_t)indicator);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_text_buffer_view_set_tab_indicator_color(
    value handle_value, value color_value) {
  CAMLparam2(handle_value, color_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  uint16_t color[4];
  if (handle == 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (!read_color(color_value, color)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }
  textBufferViewSetTabIndicatorColor(handle, color);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_text_buffer_view_set_truncate(
    value handle_value, value truncate_value) {
  CAMLparam2(handle_value, truncate_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (handle == 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  textBufferViewSetTruncate(handle, Bool_val(truncate_value));
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

CAMLprim value opentui_raw_text_buffer_view_get_line_info(value handle_value) {
  CAMLparam1(handle_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (handle == 0) {
    CAMLreturn(make_status_line_info(OPENTUI_RAW_STATUS_STALE_HANDLE, NULL));
  }

  opentui_external_line_info result;
  textBufferViewGetLineInfoDirect(handle, &result);
  CAMLreturn(make_status_line_info(OPENTUI_RAW_STATUS_OK, &result));
}

CAMLprim value opentui_raw_text_buffer_view_get_logical_line_info(
    value handle_value) {
  CAMLparam1(handle_value);

  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (handle == 0) {
    CAMLreturn(make_status_line_info(OPENTUI_RAW_STATUS_STALE_HANDLE, NULL));
  }

  opentui_external_line_info result;
  textBufferViewGetLogicalLineInfoDirect(handle, &result);
  CAMLreturn(make_status_line_info(OPENTUI_RAW_STATUS_OK, &result));
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
