#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

#include "native/opentui_abi.h"
#include "raw_status.h"

static value make_status_handle(uint32_t status, opentui_native_handle handle) {
  CAMLparam0();
  CAMLlocal3(result, status_value, handle_value);

  status_value = Val_int((int)status);
  handle_value = caml_copy_int32((int32_t)handle);
  result = caml_alloc_tuple(2);
  Store_field(result, 0, status_value);
  Store_field(result, 1, handle_value);
  CAMLreturn(result);
}

static value make_status_info(
    uint32_t status,
    const opentui_external_image_info *info) {
  CAMLparam0();
  CAMLlocalN(values, 8);
  CAMLlocal2(info_value, result);

  values[0] = caml_copy_int32((int32_t)info->width);
  values[1] = caml_copy_int32((int32_t)info->height);
  values[2] = caml_copy_int32((int32_t)info->source_width);
  values[3] = caml_copy_int32((int32_t)info->source_height);
  values[4] = caml_copy_int32((int32_t)info->format);
  values[5] = caml_copy_int32((int32_t)info->color_status);
  values[6] = caml_copy_int32((int32_t)info->orientation);
  values[7] = caml_copy_int32((int32_t)info->has_alpha);
  info_value = caml_alloc_tuple(8);
  for (int index = 0; index < 8; index++) Store_field(info_value, index, values[index]);
  result = caml_alloc_tuple(2);
  Store_field(result, 0, Val_int((int)status));
  Store_field(result, 1, info_value);
  CAMLreturn(result);
}

static bool is_bytes(value bytes) {
  return Is_block(bytes) && Tag_val(bytes) == String_tag;
}

static bool read_u32(value value_value, uint32_t *output) {
  if (!Is_block(value_value) || Tag_val(value_value) != Custom_tag) return false;
  int32_t signed_value = Int32_val(value_value);
  if (signed_value < 0) return false;
  *output = (uint32_t)signed_value;
  return true;
}

static bool read_i32(value value_value, int32_t *output) {
  if (!Is_block(value_value) || Tag_val(value_value) != Custom_tag) return false;
  *output = Int32_val(value_value);
  return true;
}

static bool read_byte_array(value bytes, uint8_t output[4]) {
  if (!is_bytes(bytes) || caml_string_length(bytes) != 4) return false;
  const uint8_t *source = (const uint8_t *)Bytes_val(bytes);
  for (int index = 0; index < 4; index++) output[index] = source[index];
  return true;
}

static bool read_floatarray(
    value array_value,
    size_t expected_length,
    float **output,
    size_t *length) {
  if (!Is_block(array_value) || Tag_val(array_value) != Double_array_tag) return false;
  mlsize_t array_length = Wosize_val(array_value);
  if (expected_length != 0 && array_length != expected_length) return false;
  if (array_length > SIZE_MAX / sizeof(float)) return false;
  float *values = NULL;
  if (array_length > 0) values = caml_stat_alloc(array_length * sizeof(*values));
  for (mlsize_t index = 0; index < array_length; index++) {
    double input = Double_field(array_value, index);
    if (!isfinite(input)) {
      if (values != NULL) caml_stat_free(values);
      return false;
    }
    values[index] = (float)input;
  }
  *output = values;
  *length = array_length;
  return true;
}

static bool buffer_is_valid(opentui_native_handle handle) {
  return handle != 0 && getBufferWidth(handle) != 0;
}

static value make_int32_array(const int32_t *values, size_t length) {
  CAMLparam0();
  CAMLlocal1(result);
  result = caml_alloc((mlsize_t)length, 0);
  for (size_t index = 0; index < length; index++) {
    Store_field(result, (mlsize_t)index, caml_copy_int32(values[index]));
  }
  CAMLreturn(result);
}

static bool is_int32_array(value array_value) {
  return Is_block(array_value) && Tag_val(array_value) == 0;
}

static bool read_int32_array_values(
    value array_value,
    int32_t *values,
    size_t expected_length) {
  if (!is_int32_array(array_value) || Wosize_val(array_value) != expected_length) {
    return false;
  }
  for (size_t index = 0; index < expected_length; index++) {
    value element = Field(array_value, (mlsize_t)index);
    if (!Is_block(element) || Tag_val(element) != Custom_tag) return false;
    values[index] = Int32_val(element);
  }
  return true;
}

CAMLprim value opentui_raw_buffer_snapshot(value buffer_value) {
  CAMLparam1(buffer_value);
  CAMLlocalN(values, 5);
  CAMLlocal2(snapshot_value, result);
  opentui_native_handle handle = (opentui_native_handle)Int32_val(buffer_value);
  uint32_t width = getBufferWidth(handle);
  uint32_t height = getBufferHeight(handle);
  if (!buffer_is_valid(handle) ||
      (height != 0 && width > UINT32_MAX / height)) {
    for (int index = 0; index < 4; index++) values[index + 1] = caml_alloc(0, 0);
    values[0] = Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE);
  } else {
    size_t cells = (size_t)width * (size_t)height;
    if (cells > SIZE_MAX / 4) {
      for (int index = 0; index < 4; index++) values[index + 1] = caml_alloc(0, 0);
      values[0] = Val_int(OPENTUI_RAW_STATUS_OUTPUT_TOO_SMALL);
    } else {
      size_t colors = cells * 4;
      uint32_t *chars = bufferGetCharPtr(handle);
      uint16_t *foreground = bufferGetFgPtr(handle);
      uint16_t *background = bufferGetBgPtr(handle);
      uint32_t *attributes = bufferGetAttributesPtr(handle);
      if (chars == NULL || foreground == NULL || background == NULL || attributes == NULL) {
        for (int index = 0; index < 4; index++) values[index + 1] = caml_alloc(0, 0);
        values[0] = Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE);
      } else {
        int32_t *char_values = caml_stat_alloc(cells * sizeof(*char_values));
        int32_t *foreground_values = caml_stat_alloc(colors * sizeof(*foreground_values));
        int32_t *background_values = caml_stat_alloc(colors * sizeof(*background_values));
        int32_t *attribute_values = caml_stat_alloc(cells * sizeof(*attribute_values));
        for (size_t index = 0; index < cells; index++) {
          char_values[index] = (int32_t)chars[index];
          attribute_values[index] = (int32_t)attributes[index];
        }
        for (size_t index = 0; index < colors; index++) {
          foreground_values[index] = (int32_t)foreground[index];
          background_values[index] = (int32_t)background[index];
        }
        values[1] = make_int32_array(char_values, cells);
        values[2] = make_int32_array(foreground_values, colors);
        values[3] = make_int32_array(background_values, colors);
        values[4] = make_int32_array(attribute_values, cells);
        caml_stat_free(char_values);
        caml_stat_free(foreground_values);
        caml_stat_free(background_values);
        caml_stat_free(attribute_values);
        values[0] = Val_int(OPENTUI_RAW_STATUS_OK);
      }
    }
  }
  snapshot_value = caml_alloc_tuple(4);
  for (int index = 0; index < 4; index++) Store_field(snapshot_value, index, values[index + 1]);
  result = caml_alloc_tuple(2);
  Store_field(result, 0, values[0]);
  Store_field(result, 1, snapshot_value);
  CAMLreturn(result);
}

CAMLprim value opentui_raw_buffer_restore(value buffer_value, value snapshot_value) {
  CAMLparam2(buffer_value, snapshot_value);
  if (!Is_block(snapshot_value) || Wosize_val(snapshot_value) != 4) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }
  opentui_native_handle handle = (opentui_native_handle)Int32_val(buffer_value);
  if (!buffer_is_valid(handle)) CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  uint32_t width = getBufferWidth(handle);
  uint32_t height = getBufferHeight(handle);
  if (height != 0 && width > UINT32_MAX / height) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }
  size_t cells = (size_t)width * (size_t)height;
  if (cells > SIZE_MAX / 4) CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  size_t colors = cells * 4;
  int32_t *chars = caml_stat_alloc(cells * sizeof(*chars));
  int32_t *foreground = caml_stat_alloc(colors * sizeof(*foreground));
  int32_t *background = caml_stat_alloc(colors * sizeof(*background));
  int32_t *attributes = caml_stat_alloc(cells * sizeof(*attributes));
  bool valid = read_int32_array_values(Field(snapshot_value, 0), chars, cells)
      && read_int32_array_values(Field(snapshot_value, 1), foreground, colors)
      && read_int32_array_values(Field(snapshot_value, 2), background, colors)
      && read_int32_array_values(Field(snapshot_value, 3), attributes, cells);
  if (valid) {
    uint32_t *native_chars = bufferGetCharPtr(handle);
    uint16_t *native_foreground = bufferGetFgPtr(handle);
    uint16_t *native_background = bufferGetBgPtr(handle);
    uint32_t *native_attributes = bufferGetAttributesPtr(handle);
    valid = native_chars != NULL && native_foreground != NULL
        && native_background != NULL && native_attributes != NULL;
    if (valid) {
      for (size_t index = 0; index < cells; index++) {
        native_chars[index] = (uint32_t)chars[index];
        native_attributes[index] = (uint32_t)attributes[index];
      }
      for (size_t index = 0; index < colors; index++) {
        native_foreground[index] = (uint16_t)foreground[index];
        native_background[index] = (uint16_t)background[index];
      }
    }
  }
  caml_stat_free(chars);
  caml_stat_free(foreground);
  caml_stat_free(background);
  caml_stat_free(attributes);
  CAMLreturn(Val_int(valid ? OPENTUI_RAW_STATUS_OK : OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
}

CAMLprim value opentui_raw_image_info(value bytes_value) {
  CAMLparam1(bytes_value);
  opentui_external_image_info info = {0};
  if (!is_bytes(bytes_value) || caml_string_length(bytes_value) == 0
      || caml_string_length(bytes_value) > UINT32_MAX) {
    CAMLreturn(make_status_info(7, &info));
  }
  uint32_t status = imageInfo(
      (const uint8_t *)Bytes_val(bytes_value),
      (uint32_t)caml_string_length(bytes_value),
      &info);
  CAMLreturn(make_status_info(status, &info));
}

CAMLprim value opentui_raw_image_decode(value bytes_value) {
  CAMLparam1(bytes_value);
  opentui_native_handle handle = 0;
  if (!is_bytes(bytes_value) || caml_string_length(bytes_value) == 0
      || caml_string_length(bytes_value) > UINT32_MAX) {
    CAMLreturn(make_status_handle(7, 0));
  }
  uint32_t status = imageDecode(
      (const uint8_t *)Bytes_val(bytes_value),
      (uint32_t)caml_string_length(bytes_value),
      &handle);
  CAMLreturn(make_status_handle(status, handle));
}

CAMLprim value opentui_raw_image_create_from_rgba(
    value pixels_value,
    value width_value,
    value height_value,
    value stride_value) {
  CAMLparam4(pixels_value, width_value, height_value, stride_value);
  if (!is_bytes(pixels_value)) CAMLreturn(make_status_handle(7, 0));
  uint32_t width, height, stride;
  if (!read_u32(width_value, &width) || !read_u32(height_value, &height)
      || !read_u32(stride_value, &stride)) {
    CAMLreturn(make_status_handle(7, 0));
  }
  opentui_native_handle handle = 0;
  uint32_t status = imageCreateFromRgba(
      (const uint8_t *)Bytes_val(pixels_value),
      (uint64_t)caml_string_length(pixels_value),
      width,
      height,
      stride,
      &handle);
  CAMLreturn(make_status_handle(status, handle));
}

CAMLprim value opentui_raw_image_destroy(value handle_value) {
  CAMLparam1(handle_value);
  imageDestroy((opentui_native_handle)Int32_val(handle_value));
  CAMLreturn(Val_unit);
}

CAMLprim value opentui_raw_image_retain(value handle_value) {
  CAMLparam1(handle_value);
  opentui_native_handle handle = 0;
  uint32_t status = imageRetain(
      (opentui_native_handle)Int32_val(handle_value), &handle);
  CAMLreturn(make_status_handle(status, handle));
}

CAMLprim value opentui_raw_image_get_info(value handle_value) {
  CAMLparam1(handle_value);
  opentui_external_image_info info = {0};
  uint32_t status = imageGetInfo(
      (opentui_native_handle)Int32_val(handle_value), &info);
  CAMLreturn(make_status_info(status, &info));
}

CAMLprim value opentui_raw_image_materialize(value handle_value) {
  CAMLparam1(handle_value);
  CAMLreturn(Val_int((int)imageMaterialize(
      (opentui_native_handle)Int32_val(handle_value))));
}

CAMLprim value opentui_raw_image_ensure_encoded_png(value handle_value) {
  CAMLparam1(handle_value);
  CAMLreturn(Val_int((int)imageEnsureEncodedPng(
      (opentui_native_handle)Int32_val(handle_value))));
}

static value image_unary_handle(
    value handle_value,
    uint32_t (*operation)(opentui_native_handle, opentui_native_handle *)) {
  CAMLparam1(handle_value);
  opentui_native_handle output = 0;
  uint32_t status = operation(
      (opentui_native_handle)Int32_val(handle_value), &output);
  CAMLreturn(make_status_handle(status, output));
}

CAMLprim value opentui_raw_image_clone(value handle_value) {
  return image_unary_handle(handle_value, imageClone);
}

CAMLprim value opentui_raw_image_copy_pixels(
    value handle_value,
    value destination_value,
    value stride_value,
    value bgra_value) {
  CAMLparam4(handle_value, destination_value, stride_value, bgra_value);
  if (!is_bytes(destination_value)) CAMLreturn(Val_int(7));
  uint32_t stride;
  if (!read_u32(stride_value, &stride) || !Is_long(bgra_value)
      || (Long_val(bgra_value) != 0 && Long_val(bgra_value) != 1)) {
    CAMLreturn(Val_int(7));
  }
  uint32_t status = imageCopyPixels(
      (opentui_native_handle)Int32_val(handle_value),
      (uint8_t *)Bytes_val(destination_value),
      (uint64_t)caml_string_length(destination_value),
      stride,
      (uint8_t)Long_val(bgra_value));
  CAMLreturn(Val_int((int)status));
}

CAMLprim value opentui_raw_image_resize(value handle_value, value args_value) {
  CAMLparam2(handle_value, args_value);
  if (!Is_block(args_value) || Wosize_val(args_value) != 3) CAMLreturn(make_status_handle(7, 0));
  uint32_t width, height, filter;
  if (!read_u32(Field(args_value, 0), &width)
      || !read_u32(Field(args_value, 1), &height)
      || !read_u32(Field(args_value, 2), &filter)) {
    CAMLreturn(make_status_handle(7, 0));
  }
  opentui_native_handle output = 0;
  uint32_t status = imageResize(
      (opentui_native_handle)Int32_val(handle_value), width, height, filter,
      &output);
  CAMLreturn(make_status_handle(status, output));
}

CAMLprim value opentui_raw_image_extract(value handle_value, value args_value) {
  CAMLparam2(handle_value, args_value);
  if (!Is_block(args_value) || Wosize_val(args_value) != 4) CAMLreturn(make_status_handle(7, 0));
  uint32_t left, top, width, height;
  if (!read_u32(Field(args_value, 0), &left)
      || !read_u32(Field(args_value, 1), &top)
      || !read_u32(Field(args_value, 2), &width)
      || !read_u32(Field(args_value, 3), &height)) {
    CAMLreturn(make_status_handle(7, 0));
  }
  opentui_native_handle output = 0;
  uint32_t status = imageExtract(
      (opentui_native_handle)Int32_val(handle_value), left, top, width, height,
      &output);
  CAMLreturn(make_status_handle(status, output));
}

CAMLprim value opentui_raw_image_extend(value handle_value, value args_value) {
  CAMLparam2(handle_value, args_value);
  if (!Is_block(args_value) || Wosize_val(args_value) != 5) CAMLreturn(make_status_handle(7, 0));
  uint32_t top, right, bottom, left;
  uint8_t background[4];
  if (!read_u32(Field(args_value, 0), &top)
      || !read_u32(Field(args_value, 1), &right)
      || !read_u32(Field(args_value, 2), &bottom)
      || !read_u32(Field(args_value, 3), &left)
      || !read_byte_array(Field(args_value, 4), background)) {
    CAMLreturn(make_status_handle(7, 0));
  }
  opentui_native_handle output = 0;
  uint32_t status = imageExtend(
      (opentui_native_handle)Int32_val(handle_value), top, right, bottom, left,
      background, &output);
  CAMLreturn(make_status_handle(status, output));
}

CAMLprim value opentui_raw_image_transform(value handle_value, value operation_value) {
  CAMLparam2(handle_value, operation_value);
  uint32_t operation;
  if (!read_u32(operation_value, &operation)) CAMLreturn(make_status_handle(7, 0));
  opentui_native_handle output = 0;
  uint32_t status = imageTransform(
      (opentui_native_handle)Int32_val(handle_value), operation, &output);
  CAMLreturn(make_status_handle(status, output));
}

CAMLprim value opentui_raw_image_composite(
    value base_value,
    value overlay_value,
    value args_value) {
  CAMLparam3(base_value, overlay_value, args_value);
  if (!Is_block(args_value) || Wosize_val(args_value) != 4) CAMLreturn(make_status_handle(7, 0));
  int32_t left, top;
  uint32_t blend;
  if (!read_i32(Field(args_value, 0), &left)
      || !read_i32(Field(args_value, 1), &top)
      || !read_u32(Field(args_value, 2), &blend)
      || !Is_long(Field(args_value, 3))
      || Long_val(Field(args_value, 3)) < 0
      || Long_val(Field(args_value, 3)) > 255) {
    CAMLreturn(make_status_handle(7, 0));
  }
  opentui_native_handle output = 0;
  uint32_t status = imageComposite(
      (opentui_native_handle)Int32_val(base_value),
      (opentui_native_handle)Int32_val(overlay_value), left, top, blend,
      (uint8_t)Long_val(Field(args_value, 3)), &output);
  CAMLreturn(make_status_handle(status, output));
}

static bool read_matrix_and_mask(
    value matrix_value,
    value mask_value,
    float **matrix,
    float **mask,
    uint32_t *mask_count) {
  size_t matrix_length, mask_length;
  if (!read_floatarray(matrix_value, 16, matrix, &matrix_length)
      || !read_floatarray(mask_value, 0, mask, &mask_length)
      || mask_length % 3 != 0
      || mask_length / 3 > UINT32_MAX) {
    if (*matrix != NULL) caml_stat_free(*matrix);
    if (*mask != NULL) caml_stat_free(*mask);
    *matrix = NULL;
    *mask = NULL;
    return false;
  }
  *mask_count = (uint32_t)(mask_length / 3);
  return true;
}

CAMLprim value opentui_raw_buffer_draw_image(value buffer_value, value args_value) {
  CAMLparam2(buffer_value, args_value);
  if (!Is_block(args_value) || Wosize_val(args_value) != 12) CAMLreturn(Val_int(1));
  int32_t x, y;
  uint32_t width, height, pixel_width, pixel_height, source_x, source_y,
      source_width, source_height, protocol;
  if (!read_i32(Field(args_value, 0), &x)
      || !read_i32(Field(args_value, 1), &y)
      || !read_u32(Field(args_value, 2), &width)
      || !read_u32(Field(args_value, 3), &height)
      || !read_u32(Field(args_value, 4), &pixel_width)
      || !read_u32(Field(args_value, 5), &pixel_height)
      || !read_u32(Field(args_value, 6), &source_x)
      || !read_u32(Field(args_value, 7), &source_y)
      || !read_u32(Field(args_value, 8), &source_width)
      || !read_u32(Field(args_value, 9), &source_height)
      || !read_u32(Field(args_value, 10), &protocol)
      || protocol > 3
      || !Is_block(Field(args_value, 11))
      || Tag_val(Field(args_value, 11)) != Custom_tag) {
    CAMLreturn(Val_int(1));
  }
  opentui_external_image_draw_options options = {
      x, y, width, height, pixel_width, pixel_height, source_x, source_y,
      source_width, source_height, protocol};
  if (!buffer_is_valid((opentui_native_handle)Int32_val(buffer_value))) {
    CAMLreturn(Val_int(2));
  }
  uint8_t drawn = bufferDrawImage(
      (opentui_native_handle)Int32_val(buffer_value),
      (opentui_native_handle)Int32_val(Field(args_value, 11)),
      &options);
  (void)drawn;
  CAMLreturn(Val_int(0));
}

CAMLprim value opentui_raw_buffer_color_matrix(
    value buffer_value,
    value matrix_value,
    value mask_value,
    value strength_value,
    value target_value) {
  CAMLparam5(buffer_value, matrix_value, mask_value, strength_value, target_value);
  float *matrix = NULL;
  float *mask = NULL;
  uint32_t mask_count = 0;
  if (!read_matrix_and_mask(matrix_value, mask_value, &matrix, &mask, &mask_count)
      || !Is_block(strength_value) || Tag_val(strength_value) != Double_tag
      || !Is_long(target_value) || Long_val(target_value) < 1
      || Long_val(target_value) > 3) {
    if (matrix != NULL) caml_stat_free(matrix);
    if (mask != NULL) caml_stat_free(mask);
    CAMLreturn(Val_int(1));
  }
  if (!buffer_is_valid((opentui_native_handle)Int32_val(buffer_value))) {
    caml_stat_free(matrix);
    if (mask != NULL) caml_stat_free(mask);
    CAMLreturn(Val_int(2));
  }
  bufferColorMatrix(
      (opentui_native_handle)Int32_val(buffer_value), matrix, mask, mask_count,
      (float)Double_val(strength_value), (uint8_t)Long_val(target_value));
  caml_stat_free(matrix);
  if (mask != NULL) caml_stat_free(mask);
  CAMLreturn(Val_int(0));
}

CAMLprim value opentui_raw_buffer_color_matrix_uniform(
    value buffer_value,
    value matrix_value,
    value strength_value,
    value target_value) {
  CAMLparam4(buffer_value, matrix_value, strength_value, target_value);
  float *matrix = NULL;
  size_t matrix_length;
  if (!read_floatarray(matrix_value, 16, &matrix, &matrix_length)
      || !Is_block(strength_value) || Tag_val(strength_value) != Double_tag
      || !Is_long(target_value) || Long_val(target_value) < 1
      || Long_val(target_value) > 3) {
    if (matrix != NULL) caml_stat_free(matrix);
    CAMLreturn(Val_int(1));
  }
  if (!buffer_is_valid((opentui_native_handle)Int32_val(buffer_value))) {
    caml_stat_free(matrix);
    CAMLreturn(Val_int(2));
  }
  bufferColorMatrixUniform(
      (opentui_native_handle)Int32_val(buffer_value), matrix,
      (float)Double_val(strength_value), (uint8_t)Long_val(target_value));
  caml_stat_free(matrix);
  CAMLreturn(Val_int(0));
}
