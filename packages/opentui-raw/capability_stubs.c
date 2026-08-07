#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#include <stdbool.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#include "native/opentui_abi.h"
#include "raw_status.h"

static bool renderer_is_valid(opentui_native_handle handle) {
  return handle != 0 && getCurrentBuffer(handle) != 0;
}

static bool copy_borrowed_string(
    const uint8_t *source,
    size_t length,
    uint8_t **output) {
  *output = NULL;
  if (length > UINT32_MAX || (length != 0 && source == NULL)) {
    return false;
  }
  if (length == 0) {
    return true;
  }

  uint8_t *copy = malloc(length);
  if (copy == NULL) {
    return false;
  }
  memcpy(copy, source, length);
  *output = copy;
  return true;
}

static bool copy_native_string(
    value *output,
    const uint8_t *source,
    size_t length) {
  if (length > UINT32_MAX || (length != 0 && source == NULL)) {
    return false;
  }

  *output = caml_alloc_string((mlsize_t)length);
  if (length != 0) {
    memcpy(Bytes_val(*output), source, length);
  }
  return true;
}

static value make_status_capabilities(
    int status,
    const opentui_external_capabilities *capabilities,
    value name,
    value version) {
  CAMLparam2(name, version);
  CAMLlocal3(result, fields, fields_option);

  if (status == OPENTUI_RAW_STATUS_OK) {
    fields = caml_alloc_tuple(24);
    Store_field(fields, 0, Val_bool(capabilities->kitty_keyboard));
    Store_field(fields, 1, Val_bool(capabilities->kitty_graphics));
    Store_field(fields, 2, Val_bool(capabilities->rgb));
    Store_field(fields, 3, Val_bool(capabilities->ansi256));
    Store_field(fields, 4, Val_int(capabilities->unicode));
    Store_field(fields, 5, Val_bool(capabilities->sgr_pixels));
    Store_field(fields, 6, Val_bool(capabilities->color_scheme_updates));
    Store_field(fields, 7, Val_bool(capabilities->explicit_width));
    Store_field(fields, 8, Val_bool(capabilities->scaled_text));
    Store_field(fields, 9, Val_bool(capabilities->sixel));
    Store_field(fields, 10, Val_bool(capabilities->focus_tracking));
    Store_field(fields, 11, Val_bool(capabilities->sync));
    Store_field(fields, 12, Val_bool(capabilities->bracketed_paste));
    Store_field(fields, 13, Val_bool(capabilities->hyperlinks));
    Store_field(fields, 14, Val_bool(capabilities->osc52));
    Store_field(fields, 15, Val_bool(capabilities->notifications));
    Store_field(fields, 16, Val_bool(capabilities->explicit_cursor_positioning));
    Store_field(fields, 17, Val_bool(capabilities->remote));
    Store_field(fields, 18, Val_int(capabilities->multiplexer));
    Store_field(fields, 19, Val_int(capabilities->image_protocol));
    Store_field(fields, 20, name);
    Store_field(fields, 21, version);
    Store_field(fields, 22, Val_bool(capabilities->term_from_xtversion));
    Store_field(fields, 23, Val_int(capabilities->osc52_support));
    fields_option = caml_alloc(1, 0);
    Store_field(fields_option, 0, fields);
  } else {
    fields_option = Val_none;
  }

  result = caml_alloc_tuple(2);
  Store_field(result, 0, Val_int(status));
  Store_field(result, 1, fields_option);
  CAMLreturn(result);
}

CAMLprim value opentui_raw_renderer_capabilities(value renderer_value) {
  CAMLparam1(renderer_value);
  CAMLlocal2(name, version);

  opentui_native_handle renderer =
      (opentui_native_handle)Int32_val(renderer_value);
  if (!renderer_is_valid(renderer)) {
    CAMLreturn(make_status_capabilities(
        OPENTUI_RAW_STATUS_STALE_HANDLE,
        NULL,
        Val_unit,
        Val_unit));
  }

  opentui_external_capabilities capabilities;
  getTerminalCapabilities(renderer, &capabilities);
  uint8_t *name_copy = NULL;
  uint8_t *version_copy = NULL;
  if (!copy_borrowed_string(
          capabilities.term_name_ptr,
          capabilities.term_name_len,
          &name_copy)
      || !copy_borrowed_string(
          capabilities.term_version_ptr,
          capabilities.term_version_len,
          &version_copy)) {
    free(name_copy);
    free(version_copy);
    CAMLreturn(make_status_capabilities(
        OPENTUI_RAW_STATUS_NATIVE_FAILURE,
        NULL,
        Val_unit,
        Val_unit));
  }
  if (!copy_native_string(
          &name,
          name_copy,
          capabilities.term_name_len)
      || !copy_native_string(
          &version,
          version_copy,
          capabilities.term_version_len)) {
    free(name_copy);
    free(version_copy);
    CAMLreturn(make_status_capabilities(
        OPENTUI_RAW_STATUS_NATIVE_FAILURE,
        NULL,
        Val_unit,
        Val_unit));
  }
  free(name_copy);
  free(version_copy);

  CAMLreturn(make_status_capabilities(
      OPENTUI_RAW_STATUS_OK,
      &capabilities,
      name,
      version));
}

CAMLprim value opentui_raw_process_capability_response(
    value renderer_value,
    value response_value) {
  CAMLparam2(renderer_value, response_value);

  opentui_native_handle renderer =
      (opentui_native_handle)Int32_val(renderer_value);
  if (!renderer_is_valid(renderer)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }

  mlsize_t response_length = caml_string_length(response_value);
  if (response_length > UINT32_MAX) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  const uint8_t *response = response_length == 0
      ? NULL
      : (const uint8_t *)String_val(response_value);
  processCapabilityResponse(renderer, response, (uint32_t)response_length);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}
