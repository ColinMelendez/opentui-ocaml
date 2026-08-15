#include <caml/alloc.h>
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

static value make_status_int32(int status, uint32_t result_value) {
  CAMLparam0();
  CAMLlocal3(result, status_value, value_value);
  status_value = Val_int(status);
  value_value = caml_copy_int32((int32_t)result_value);
  result = caml_alloc_tuple(2);
  Store_field(result, 0, status_value);
  Store_field(result, 1, value_value);
  CAMLreturn(result);
}

static bool read_color(value color, uint16_t output[4]) {
  if (!Is_block(color) || Wosize_val(color) != 4) return false;
  for (uintnat index = 0; index < 4; index++) {
    value channel = Field(color, index);
    if (!Is_long(channel)) return false;
    intnat channel_value = Long_val(channel);
    if (channel_value < 0 || channel_value > UINT8_MAX) return false;
    output[index] = (uint16_t)channel_value;
  }
  return true;
}

static bool read_optional_color(
    value option_value,
    uint16_t output[4],
    const uint16_t **pointer) {
  if (option_value == Val_none) {
    *pointer = NULL;
    return true;
  }
  if (!Is_block(option_value) || Wosize_val(option_value) != 1
      || !read_color(Field(option_value, 0), output)) return false;
  *pointer = output;
  return true;
}

static bool is_string_value(value value_to_check) {
  return Is_block(value_to_check) && Tag_val(value_to_check) == String_tag;
}

CAMLprim value opentui_raw_syntax_style_create(value unit_value) {
  CAMLparam1(unit_value);
  opentui_native_handle handle = createSyntaxStyle();
  if (handle == 0) {
    CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_NATIVE_FAILURE, 0));
  }
  CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_OK, handle));
}

CAMLprim value opentui_raw_syntax_style_destroy(value handle_value) {
  CAMLparam1(handle_value);
  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (handle != 0) destroySyntaxStyle(handle);
  CAMLreturn(Val_unit);
}

CAMLprim value opentui_raw_syntax_style_register(
    value handle_value,
    value name_value,
    value fg_value,
    value bg_value,
    value attributes_value) {
  CAMLparam5(handle_value, name_value, fg_value, bg_value, attributes_value);
  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (handle == 0 || !is_string_value(name_value)
      || !Is_block(attributes_value)) {
    CAMLreturn(make_status_int32(OPENTUI_RAW_STATUS_INVALID_ARGUMENT, 0));
  }
  uint16_t fg[4];
  uint16_t bg[4];
  const uint16_t *fg_pointer;
  const uint16_t *bg_pointer;
  if (!read_optional_color(fg_value, fg, &fg_pointer)
      || !read_optional_color(bg_value, bg, &bg_pointer)) {
    CAMLreturn(make_status_int32(OPENTUI_RAW_STATUS_INVALID_ARGUMENT, 0));
  }
  uint32_t style_id = syntaxStyleRegister(handle,
      (const uint8_t *)String_val(name_value),
      (uint32_t)caml_string_length(name_value), fg_pointer, bg_pointer,
      (uint32_t)Int32_val(attributes_value));
  if (style_id == 0) {
    CAMLreturn(make_status_int32(OPENTUI_RAW_STATUS_NATIVE_FAILURE, 0));
  }
  CAMLreturn(make_status_int32(OPENTUI_RAW_STATUS_OK, style_id));
}

CAMLprim value opentui_raw_syntax_style_resolve(
    value handle_value,
    value name_value) {
  CAMLparam2(handle_value, name_value);
  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (handle == 0 || !is_string_value(name_value)) {
    CAMLreturn(make_status_int32(OPENTUI_RAW_STATUS_INVALID_ARGUMENT, 0));
  }
  uint32_t style_id = syntaxStyleResolveByName(handle,
      (const uint8_t *)String_val(name_value),
      (uint32_t)caml_string_length(name_value));
  CAMLreturn(make_status_int32(OPENTUI_RAW_STATUS_OK, style_id));
}

CAMLprim value opentui_raw_syntax_style_count(value handle_value) {
  CAMLparam1(handle_value);
  opentui_native_handle handle = (opentui_native_handle)Int32_val(handle_value);
  if (handle == 0) {
    CAMLreturn(make_status_int32(OPENTUI_RAW_STATUS_STALE_HANDLE, 0));
  }
  CAMLreturn(make_status_int32(OPENTUI_RAW_STATUS_OK,
      syntaxStyleGetStyleCount(handle)));
}
