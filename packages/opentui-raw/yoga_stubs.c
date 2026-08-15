#include <caml/alloc.h>
#include <caml/callback.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#include <float.h>
#include <math.h>
#include <stdbool.h>
#include <stdint.h>

#include "native/opentui_abi.h"
#include "raw_status.h"

#define OPENTUI_RAW_YOGA_NODE_CAPACITY 4096

typedef struct opentui_raw_yoga_node_slot {
  uint16_t generation;
  bool alive;
  bool native_renderable_attached;
  bool native_measure_attached;
  opentui_yoga_node_ref node;
  uint32_t parent_handle;
} opentui_raw_yoga_node_slot;

static opentui_raw_yoga_node_slot yoga_nodes[OPENTUI_RAW_YOGA_NODE_CAPACITY];

static value yoga_measure_callback = Val_unit;
static bool yoga_measure_callback_registered = false;

static void raw_yoga_measure_callback(
    void *node,
    float width,
    uint32_t width_mode,
    float height,
    uint32_t height_mode) {
  CAMLparam0();
  CAMLlocal5(node_value, arguments, result, width_value, height_value);

  if (!yoga_measure_callback_registered) {
    yogaStoreMeasureResult(NAN, NAN);
    CAMLreturn0;
  }

  node_value = caml_copy_nativeint((intnat)node);
  arguments = caml_alloc_tuple(5);
  Store_field(arguments, 0, node_value);
  Store_field(arguments, 1, caml_copy_double((double)width));
  Store_field(arguments, 2, caml_copy_int32((int32_t)width_mode));
  Store_field(arguments, 3, caml_copy_double((double)height));
  Store_field(arguments, 4, caml_copy_int32((int32_t)height_mode));
  result = caml_callback_exn(yoga_measure_callback, arguments);
  if (!Is_exception_result(result)
      && Is_block(result)
      && Wosize_val(result) == 2
      && Is_block(Field(result, 0))
      && Tag_val(Field(result, 0)) == Double_tag
      && Is_block(Field(result, 1))
      && Tag_val(Field(result, 1)) == Double_tag) {
    width_value = Field(result, 0);
    height_value = Field(result, 1);
    yogaStoreMeasureResult(
        (float)Double_val(width_value),
        (float)Double_val(height_value));
  } else {
    yogaStoreMeasureResult(NAN, NAN);
  }

  CAMLreturn0;
}

static uint32_t yoga_handle(uint32_t slot, uint16_t generation) {
  return ((uint32_t)generation << 16) | slot;
}

static uint32_t yoga_slot_index(uint32_t handle) {
  return handle & UINT32_C(0xffff);
}

static uint16_t yoga_generation(uint32_t handle) {
  return (uint16_t)(handle >> 16);
}

static uint16_t yoga_next_generation(uint16_t generation) {
  return generation == UINT16_MAX ? 1 : (uint16_t)(generation + 1);
}

static uint32_t yoga_allocate_node(opentui_raw_yoga_node_slot **output) {
  for (uint32_t index = 1; index < OPENTUI_RAW_YOGA_NODE_CAPACITY; index++) {
    opentui_raw_yoga_node_slot *slot = &yoga_nodes[index];
    if (!slot->alive) {
      slot->generation = slot->generation == 0
          ? 1
          : yoga_next_generation(slot->generation);
      slot->alive = true;
      slot->native_renderable_attached = false;
      slot->native_measure_attached = false;
      slot->node = NULL;
      slot->parent_handle = 0;
      *output = slot;
      return yoga_handle(index, slot->generation);
    }
  }

  return 0;
}

static opentui_raw_yoga_node_slot *yoga_node_from_handle(uint32_t handle) {
  uint32_t index = yoga_slot_index(handle);
  if (index == 0 || index >= OPENTUI_RAW_YOGA_NODE_CAPACITY) {
    return NULL;
  }

  opentui_raw_yoga_node_slot *slot = &yoga_nodes[index];
  if (!slot->alive || slot->generation != yoga_generation(handle)) {
    return NULL;
  }

  return slot;
}

static void yoga_release_node(uint32_t handle) {
  uint32_t index = yoga_slot_index(handle);
  opentui_raw_yoga_node_slot *slot = &yoga_nodes[index];
  slot->alive = false;
  slot->native_renderable_attached = false;
  slot->native_measure_attached = false;
  slot->node = NULL;
  slot->parent_handle = 0;
}

static void yoga_release_subtree_slots(uint32_t root_handle) {
  uint32_t pending[OPENTUI_RAW_YOGA_NODE_CAPACITY];
  uint32_t pending_count = 1;
  pending[0] = root_handle;

  while (pending_count > 0) {
    uint32_t handle = pending[--pending_count];
    for (uint32_t index = 1; index < OPENTUI_RAW_YOGA_NODE_CAPACITY; index++) {
      opentui_raw_yoga_node_slot *candidate = &yoga_nodes[index];
      if (candidate->alive && candidate->parent_handle == handle) {
        uint32_t child_handle = yoga_handle(index, candidate->generation);
        pending[pending_count++] = child_handle;
      }
    }

    yoga_release_node(handle);
  }
}

static bool yoga_subtree_has_native_renderable(uint32_t root_handle) {
  uint32_t pending[OPENTUI_RAW_YOGA_NODE_CAPACITY];
  uint32_t pending_count = 1;
  pending[0] = root_handle;

  while (pending_count > 0) {
    uint32_t handle = pending[--pending_count];
    opentui_raw_yoga_node_slot *node = yoga_node_from_handle(handle);
    if (node == NULL) {
      return true;
    }
    if (node->native_renderable_attached) {
      return true;
    }

    for (uint32_t index = 1; index < OPENTUI_RAW_YOGA_NODE_CAPACITY; index++) {
      opentui_raw_yoga_node_slot *candidate = &yoga_nodes[index];
      if (candidate->alive && candidate->parent_handle == handle) {
        if (pending_count == OPENTUI_RAW_YOGA_NODE_CAPACITY) {
          return true;
        }
        pending[pending_count++] = yoga_handle(index, candidate->generation);
      }
    }
  }

  return false;
}

static bool yoga_would_create_cycle(uint32_t parent_handle, uint32_t child_handle) {
  uint32_t ancestor_handle = parent_handle;
  while (ancestor_handle != 0) {
    if (ancestor_handle == child_handle) {
      return true;
    }

    opentui_raw_yoga_node_slot *ancestor =
        yoga_node_from_handle(ancestor_handle);
    if (ancestor == NULL) {
      return true;
    }
    ancestor_handle = ancestor->parent_handle;
  }

  return false;
}

static value make_status_handle(int status, uint32_t handle) {
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
  CAMLlocal3(result, status_value, int32_value);

  status_value = Val_int(status);
  int32_value = caml_copy_int32(result_value);
  result = caml_alloc_tuple(2);
  Store_field(result, 0, status_value);
  Store_field(result, 1, int32_value);
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

static value make_status_layout(
    int status,
    const opentui_external_yoga_layout *layout) {
  CAMLparam0();
  CAMLlocalN(roots, 9);

  if (status == OPENTUI_RAW_STATUS_OK) {
    roots[2] = caml_alloc_tuple(6);
    roots[3] = caml_copy_double(layout->left);
    roots[4] = caml_copy_double(layout->top);
    roots[5] = caml_copy_double(layout->right);
    roots[6] = caml_copy_double(layout->bottom);
    roots[7] = caml_copy_double(layout->width);
    roots[8] = caml_copy_double(layout->height);
    Store_field(roots[2], 0, roots[3]);
    Store_field(roots[2], 1, roots[4]);
    Store_field(roots[2], 2, roots[5]);
    Store_field(roots[2], 3, roots[6]);
    Store_field(roots[2], 4, roots[7]);
    Store_field(roots[2], 5, roots[8]);
    roots[1] = caml_alloc(1, 0);
    Store_field(roots[1], 0, roots[2]);
  } else {
    roots[1] = Val_none;
  }

  roots[0] = caml_alloc_tuple(2);
  Store_field(roots[0], 0, Val_int(status));
  Store_field(roots[0], 1, roots[1]);
  CAMLreturn(roots[0]);
}

static int yoga_validate_finite_float(value input_value, float *output) {
  double input = Double_val(input_value);
  if (!isfinite(input) || input < -(double)FLT_MAX || input > (double)FLT_MAX) {
    return OPENTUI_RAW_STATUS_INVALID_ARGUMENT;
  }

  *output = (float)input;
  return OPENTUI_RAW_STATUS_OK;
}

static int yoga_validate_layout_dimension(value input_value, float *output) {
  double input = Double_val(input_value);
  if (isnan(input)) {
    *output = NAN;
    return OPENTUI_RAW_STATUS_OK;
  }
  if (!isfinite(input) || input < 0.0 || input > (double)FLT_MAX) {
    return OPENTUI_RAW_STATUS_INVALID_ARGUMENT;
  }

  *output = (float)input;
  return OPENTUI_RAW_STATUS_OK;
}

static int yoga_validate_style_value(
    value unit_value,
    value numeric_value,
    float *output) {
  int32_t unit = Int32_val(unit_value);
  if (unit == 0 || unit == 3) {
    *output = NAN;
    return OPENTUI_RAW_STATUS_OK;
  }
  if (unit != 1 && unit != 2) {
    return OPENTUI_RAW_STATUS_INVALID_ARGUMENT;
  }

  return yoga_validate_finite_float(numeric_value, output);
}

static bool yoga_valid_enum_value(int32_t kind, int32_t value) {
  switch (kind) {
    case 0:
      return value >= 0 && value <= 2;
    case 1:
      return value >= 0 && value <= 3;
    case 2:
      return value >= 0 && value <= 5;
    case 3:
    case 4:
    case 5:
      return value >= 0 && value <= 8;
    case 6:
      return value >= 0 && value <= 2;
    case 7:
      return value >= 0 && value <= 2;
    case 8:
    case 9:
      return value >= 0 && value <= 2;
    case 10:
      return value >= 0 && value <= 1;
    default:
      return false;
  }
}

static bool yoga_valid_value_location(int32_t kind, int32_t edge_or_gutter) {
  switch (kind) {
    case 0:
    case 1:
    case 2:
    case 3:
    case 4:
    case 5:
    case 6:
      return edge_or_gutter == 0;
    case 7:
    case 8:
    case 9:
      return edge_or_gutter >= 0 && edge_or_gutter <= 8;
    case 10:
      return edge_or_gutter >= 0 && edge_or_gutter <= 2;
    default:
      return false;
  }
}

CAMLprim value opentui_raw_yoga_node_create(value unit_value) {
  CAMLparam1(unit_value);

  opentui_raw_yoga_node_slot *slot;
  uint32_t handle = yoga_allocate_node(&slot);
  if (handle == 0) {
    CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_NATIVE_FAILURE, 0));
  }

  slot->node = yogaNodeCreateForOpenTUI();
  if (slot->node == NULL) {
    yoga_release_node(handle);
    CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_NATIVE_FAILURE, 0));
  }

  CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_OK, handle));
}

CAMLprim value opentui_raw_yoga_node_free(value node_value) {
  CAMLparam1(node_value);

  uint32_t handle = (uint32_t)Int32_val(node_value);
  opentui_raw_yoga_node_slot *node = yoga_node_from_handle(handle);
  if (node == NULL) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (node->native_renderable_attached
      || node->parent_handle != 0
      || yogaNodeGetChildCount(node->node) != 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  yogaNodeFree(node->node);
  yoga_release_node(handle);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_yoga_node_free_recursive(value node_value) {
  CAMLparam1(node_value);

  uint32_t handle = (uint32_t)Int32_val(node_value);
  opentui_raw_yoga_node_slot *node = yoga_node_from_handle(handle);
  if (node == NULL) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (node->native_renderable_attached || node->parent_handle != 0
      || yoga_subtree_has_native_renderable(handle)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  yogaNodeFreeRecursive(node->node);
  yoga_release_subtree_slots(handle);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_yoga_node_insert_child(
    value parent_value,
    value child_value,
    value index_value) {
  CAMLparam3(parent_value, child_value, index_value);

  int32_t signed_index = Int32_val(index_value);
  if (signed_index < 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  uint32_t parent_handle = (uint32_t)Int32_val(parent_value);
  uint32_t child_handle = (uint32_t)Int32_val(child_value);
  opentui_raw_yoga_node_slot *parent = yoga_node_from_handle(parent_handle);
  opentui_raw_yoga_node_slot *child = yoga_node_from_handle(child_handle);
  if (parent == NULL || child == NULL) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (parent->native_measure_attached) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }
  if (parent_handle == child_handle || child->parent_handle != 0
      || yoga_would_create_cycle(parent_handle, child_handle)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }
  if ((uint32_t)signed_index > yogaNodeGetChildCount(parent->node)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  yogaNodeInsertChild(parent->node, child->node, (uint32_t)signed_index);
  child->parent_handle = parent_handle;
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_yoga_node_remove_child(
    value parent_value,
    value child_value) {
  CAMLparam2(parent_value, child_value);

  uint32_t parent_handle = (uint32_t)Int32_val(parent_value);
  uint32_t child_handle = (uint32_t)Int32_val(child_value);
  opentui_raw_yoga_node_slot *parent = yoga_node_from_handle(parent_handle);
  opentui_raw_yoga_node_slot *child = yoga_node_from_handle(child_handle);
  if (parent == NULL || child == NULL) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (child->parent_handle != parent_handle) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  yogaNodeRemoveChild(parent->node, child->node);
  child->parent_handle = 0;
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_yoga_node_move_child(
    value parent_value,
    value child_value,
    value index_value) {
  CAMLparam3(parent_value, child_value, index_value);

  int32_t signed_index = Int32_val(index_value);
  if (signed_index < 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  uint32_t parent_handle = (uint32_t)Int32_val(parent_value);
  uint32_t child_handle = (uint32_t)Int32_val(child_value);
  opentui_raw_yoga_node_slot *parent = yoga_node_from_handle(parent_handle);
  opentui_raw_yoga_node_slot *child = yoga_node_from_handle(child_handle);
  if (parent == NULL || child == NULL) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (child->parent_handle != parent_handle) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }
  if ((uint32_t)signed_index >= yogaNodeGetChildCount(parent->node)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  yogaNodeRemoveChild(parent->node, child->node);
  yogaNodeInsertChild(parent->node, child->node, (uint32_t)signed_index);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_yoga_node_child_count(value node_value) {
  CAMLparam1(node_value);

  uint32_t handle = (uint32_t)Int32_val(node_value);
  opentui_raw_yoga_node_slot *node = yoga_node_from_handle(handle);
  if (node == NULL) {
    CAMLreturn(make_status_int32(OPENTUI_RAW_STATUS_STALE_HANDLE, 0));
  }

  CAMLreturn(make_status_int32(
      OPENTUI_RAW_STATUS_OK,
      (int32_t)yogaNodeGetChildCount(node->node)));
}

CAMLprim value opentui_raw_yoga_node_calculate(
    value node_value,
    value width_value,
    value height_value,
    value direction_value) {
  CAMLparam4(node_value, width_value, height_value, direction_value);

  uint32_t handle = (uint32_t)Int32_val(node_value);
  opentui_raw_yoga_node_slot *node = yoga_node_from_handle(handle);
  if (node == NULL) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }

  float width;
  float height;
  int width_status = yoga_validate_layout_dimension(width_value, &width);
  int height_status = yoga_validate_layout_dimension(height_value, &height);
  int32_t direction = Int32_val(direction_value);
  if (width_status != OPENTUI_RAW_STATUS_OK
      || height_status != OPENTUI_RAW_STATUS_OK
      || direction < 0 || direction > 2) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  yogaNodeCalculateLayout(node->node, width, height, (uint32_t)direction);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_yoga_node_is_dirty(value node_value) {
  CAMLparam1(node_value);

  uint32_t handle = (uint32_t)Int32_val(node_value);
  opentui_raw_yoga_node_slot *node = yoga_node_from_handle(handle);
  if (node == NULL) {
    CAMLreturn(make_status_bool(OPENTUI_RAW_STATUS_STALE_HANDLE, false));
  }

  CAMLreturn(make_status_bool(OPENTUI_RAW_STATUS_OK, yogaNodeIsDirty(node->node)));
}

CAMLprim value opentui_raw_yoga_node_mark_dirty(value node_value) {
  CAMLparam1(node_value);

  uint32_t handle = (uint32_t)Int32_val(node_value);
  opentui_raw_yoga_node_slot *node = yoga_node_from_handle(handle);
  if (node == NULL) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (!node->native_measure_attached) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  yogaNodeMarkDirty(node->node);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_yoga_node_has_new_layout(value node_value) {
  CAMLparam1(node_value);

  uint32_t handle = (uint32_t)Int32_val(node_value);
  opentui_raw_yoga_node_slot *node = yoga_node_from_handle(handle);
  if (node == NULL) {
    CAMLreturn(make_status_bool(OPENTUI_RAW_STATUS_STALE_HANDLE, false));
  }

  CAMLreturn(make_status_bool(
      OPENTUI_RAW_STATUS_OK,
      yogaNodeGetHasNewLayout(node->node)));
}

CAMLprim value opentui_raw_yoga_node_mark_layout_seen(value node_value) {
  CAMLparam1(node_value);

  uint32_t handle = (uint32_t)Int32_val(node_value);
  opentui_raw_yoga_node_slot *node = yoga_node_from_handle(handle);
  if (node == NULL) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }

  yogaNodeSetHasNewLayout(node->node, false);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_yoga_node_style_set_value(
    value node_value,
    value kind_value,
    value edge_or_gutter_value,
    value unit_value,
    value numeric_value) {
  CAMLparam5(node_value, kind_value, edge_or_gutter_value, unit_value, numeric_value);

  uint32_t handle = (uint32_t)Int32_val(node_value);
  opentui_raw_yoga_node_slot *node = yoga_node_from_handle(handle);
  if (node == NULL) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }

  int32_t kind = Int32_val(kind_value);
  int32_t edge_or_gutter = Int32_val(edge_or_gutter_value);
  if (!yoga_valid_value_location(kind, edge_or_gutter)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  float numeric;
  int status = yoga_validate_style_value(unit_value, numeric_value, &numeric);
  if (status != OPENTUI_RAW_STATUS_OK) {
    CAMLreturn(Val_int(status));
  }

  yogaNodeStyleSetValue(
      node->node,
      (uint32_t)kind,
      (uint32_t)edge_or_gutter,
      (uint32_t)Int32_val(unit_value),
      numeric);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_yoga_node_style_set_enum(
    value node_value,
    value kind_value,
    value enum_value) {
  CAMLparam3(node_value, kind_value, enum_value);

  uint32_t handle = (uint32_t)Int32_val(node_value);
  opentui_raw_yoga_node_slot *node = yoga_node_from_handle(handle);
  if (node == NULL) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }

  int32_t kind = Int32_val(kind_value);
  int32_t enum_code = Int32_val(enum_value);
  if (!yoga_valid_enum_value(kind, enum_code)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  yogaNodeStyleSetEnum(node->node, (uint32_t)kind, (uint32_t)enum_code);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_yoga_node_style_set_float(
    value node_value,
    value kind_value,
    value numeric_value) {
  CAMLparam3(node_value, kind_value, numeric_value);

  uint32_t handle = (uint32_t)Int32_val(node_value);
  opentui_raw_yoga_node_slot *node = yoga_node_from_handle(handle);
  if (node == NULL) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  int32_t kind = Int32_val(kind_value);
  if (kind < 0 || kind > 3) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  float numeric;
  double input = Double_val(numeric_value);
  if (isnan(input)) {
    numeric = NAN;
  } else {
    int status = yoga_validate_finite_float(numeric_value, &numeric);
    if (status != OPENTUI_RAW_STATUS_OK) {
      CAMLreturn(Val_int(status));
    }
  }

  yogaNodeStyleSetFloat(node->node, (uint32_t)kind, numeric);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_yoga_node_style_set_border(
    value node_value,
    value edge_value,
    value numeric_value) {
  CAMLparam3(node_value, edge_value, numeric_value);

  uint32_t handle = (uint32_t)Int32_val(node_value);
  opentui_raw_yoga_node_slot *node = yoga_node_from_handle(handle);
  if (node == NULL) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  int32_t edge = Int32_val(edge_value);
  if (edge < 0 || edge > 8) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  float numeric;
  double input = Double_val(numeric_value);
  if (isnan(input)) {
    numeric = NAN;
  } else {
    int status = yoga_validate_finite_float(numeric_value, &numeric);
    if (status != OPENTUI_RAW_STATUS_OK) {
      CAMLreturn(Val_int(status));
    }
  }

  yogaNodeStyleSetBorder(node->node, (uint32_t)edge, numeric);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_yoga_node_layout(value node_value) {
  CAMLparam1(node_value);

  uint32_t handle = (uint32_t)Int32_val(node_value);
  opentui_raw_yoga_node_slot *node = yoga_node_from_handle(handle);
  if (node == NULL) {
    CAMLreturn(make_status_layout(OPENTUI_RAW_STATUS_STALE_HANDLE, NULL));
  }

  opentui_external_yoga_layout layout;
  yogaNodeGetComputedLayout(node->node, &layout);
  CAMLreturn(make_status_layout(OPENTUI_RAW_STATUS_OK, &layout));
}

CAMLprim value opentui_raw_native_renderable_attach_yoga_node(
    value renderable_value,
    value node_value) {
  CAMLparam2(renderable_value, node_value);

  opentui_native_handle renderable =
      (opentui_native_handle)Int32_val(renderable_value);
  uint32_t node_handle = (uint32_t)Int32_val(node_value);
  opentui_raw_yoga_node_slot *node = yoga_node_from_handle(node_handle);
  if (renderable == 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (node == NULL) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (!nativeRenderableAttachYogaNode(renderable, node->node)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_NATIVE_FAILURE));
  }

  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_yoga_node_claim_native_renderable(value node_value) {
  CAMLparam1(node_value);

  uint32_t handle = (uint32_t)Int32_val(node_value);
  opentui_raw_yoga_node_slot *node = yoga_node_from_handle(handle);
  if (node == NULL) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  if (node->native_renderable_attached) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  node->native_renderable_attached = true;
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_yoga_node_release_native_renderable(
    value node_value) {
  CAMLparam1(node_value);

  uint32_t handle = (uint32_t)Int32_val(node_value);
  opentui_raw_yoga_node_slot *node = yoga_node_from_handle(handle);
  if (node == NULL) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }

  node->native_renderable_attached = false;
  node->native_measure_attached = false;
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_yoga_node_set_native_measure_attached(
    value node_value,
    value attached_value) {
  CAMLparam2(node_value, attached_value);

  uint32_t handle = (uint32_t)Int32_val(node_value);
  opentui_raw_yoga_node_slot *node = yoga_node_from_handle(handle);
  if (node == NULL) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  bool attached = Bool_val(attached_value);
  if (attached && !node->native_renderable_attached) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  node->native_measure_attached = attached;
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_yoga_node_set_measure_func(
    value node_value,
    value enabled_value) {
  CAMLparam2(node_value, enabled_value);

  uint32_t handle = (uint32_t)Int32_val(node_value);
  opentui_raw_yoga_node_slot *node = yoga_node_from_handle(handle);
  if (node != NULL) {
    yogaNodeSetMeasureFunc(node->node, Bool_val(enabled_value));
  }
  CAMLreturn(Val_unit);
}

CAMLprim value opentui_raw_yoga_node_unset_measure_func(value node_value) {
  CAMLparam1(node_value);

  uint32_t handle = (uint32_t)Int32_val(node_value);
  opentui_raw_yoga_node_slot *node = yoga_node_from_handle(handle);
  if (node != NULL) {
    yogaNodeUnsetMeasureFunc(node->node);
  }
  CAMLreturn(Val_unit);
}

CAMLprim value opentui_raw_yoga_node_has_measure_func(value node_value) {
  CAMLparam1(node_value);

  uint32_t handle = (uint32_t)Int32_val(node_value);
  opentui_raw_yoga_node_slot *node = yoga_node_from_handle(handle);
  CAMLreturn(Val_bool(node != NULL && yogaNodeHasMeasureFunc(node->node)));
}

CAMLprim value opentui_raw_yoga_node_pointer(value node_value) {
  CAMLparam1(node_value);

  uint32_t handle = (uint32_t)Int32_val(node_value);
  opentui_raw_yoga_node_slot *node = yoga_node_from_handle(handle);
  if (node == NULL) {
    CAMLreturn(caml_copy_nativeint(0));
  }
  CAMLreturn(caml_copy_nativeint((intnat)node->node));
}

CAMLprim value opentui_raw_yoga_set_measure_callback(value callback) {
  CAMLparam1(callback);

  if (yoga_measure_callback_registered) {
    caml_remove_global_root(&yoga_measure_callback);
    yoga_measure_callback_registered = false;
  }
  yoga_measure_callback = callback;
  caml_register_global_root(&yoga_measure_callback);
  yoga_measure_callback_registered = true;
  yogaSetMeasureCallback((const void *)&raw_yoga_measure_callback);
  CAMLreturn(Val_unit);
}

CAMLprim value opentui_raw_yoga_clear_measure_callback(value unit_value) {
  CAMLparam1(unit_value);

  yogaSetMeasureCallback(NULL);
  if (yoga_measure_callback_registered) {
    caml_remove_global_root(&yoga_measure_callback);
    yoga_measure_callback_registered = false;
  }
  yoga_measure_callback = Val_unit;
  CAMLreturn(Val_unit);
}
