#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#include <stdbool.h>
#include <float.h>
#include <stdint.h>
#include <math.h>

#include "native/opentui_abi.h"
#include "raw_status.h"

#define OPENTUI_RAW_YOGA_TREE_CAPACITY 64
#define OPENTUI_RAW_YOGA_NODE_CAPACITY 4096

typedef struct opentui_raw_yoga_tree_slot {
  uint16_t generation;
  bool alive;
  opentui_yoga_config_ref config;
  uint32_t root_handle;
} opentui_raw_yoga_tree_slot;

typedef struct opentui_raw_yoga_node_slot {
  uint16_t generation;
  bool alive;
  opentui_yoga_node_ref node;
  uint32_t tree_handle;
  uint32_t parent_handle;
} opentui_raw_yoga_node_slot;

static opentui_raw_yoga_tree_slot yoga_trees[OPENTUI_RAW_YOGA_TREE_CAPACITY];
static opentui_raw_yoga_node_slot yoga_nodes[OPENTUI_RAW_YOGA_NODE_CAPACITY];

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

static uint32_t yoga_allocate_tree(opentui_raw_yoga_tree_slot **output) {
  for (uint32_t index = 1; index < OPENTUI_RAW_YOGA_TREE_CAPACITY; index++) {
    opentui_raw_yoga_tree_slot *slot = &yoga_trees[index];
    if (!slot->alive) {
      slot->generation = slot->generation == 0
          ? 1
          : yoga_next_generation(slot->generation);
      slot->alive = true;
      slot->config = NULL;
      slot->root_handle = 0;
      *output = slot;
      return yoga_handle(index, slot->generation);
    }
  }

  return 0;
}

static uint32_t yoga_allocate_node(
    opentui_raw_yoga_node_slot **output,
    uint32_t tree_handle) {
  for (uint32_t index = 1; index < OPENTUI_RAW_YOGA_NODE_CAPACITY; index++) {
    opentui_raw_yoga_node_slot *slot = &yoga_nodes[index];
    if (!slot->alive) {
      slot->generation = slot->generation == 0
          ? 1
          : yoga_next_generation(slot->generation);
      slot->alive = true;
      slot->node = NULL;
      slot->tree_handle = tree_handle;
      slot->parent_handle = 0;
      *output = slot;
      return yoga_handle(index, slot->generation);
    }
  }

  return 0;
}

static opentui_raw_yoga_tree_slot *yoga_tree_from_handle(uint32_t handle) {
  uint32_t index = yoga_slot_index(handle);
  if (index == 0 || index >= OPENTUI_RAW_YOGA_TREE_CAPACITY) {
    return NULL;
  }

  opentui_raw_yoga_tree_slot *slot = &yoga_trees[index];
  if (!slot->alive || slot->generation != yoga_generation(handle)) {
    return NULL;
  }

  return slot;
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

static void yoga_release_tree(uint32_t handle) {
  uint32_t index = yoga_slot_index(handle);
  opentui_raw_yoga_tree_slot *slot = &yoga_trees[index];
  slot->alive = false;
  slot->config = NULL;
  slot->root_handle = 0;
}

static void yoga_release_node(uint32_t handle) {
  uint32_t index = yoga_slot_index(handle);
  opentui_raw_yoga_node_slot *slot = &yoga_nodes[index];
  slot->alive = false;
  slot->node = NULL;
  slot->tree_handle = 0;
  slot->parent_handle = 0;
}

static void yoga_release_subtree_slots(
    uint32_t tree_handle,
    uint32_t root_handle) {
  for (uint32_t index = 1; index < OPENTUI_RAW_YOGA_NODE_CAPACITY; index++) {
    opentui_raw_yoga_node_slot *node = &yoga_nodes[index];
    if (node->alive
        && node->tree_handle == tree_handle
        && node->parent_handle == root_handle) {
      uint32_t child_handle = yoga_handle(index, node->generation);
      yoga_release_subtree_slots(tree_handle, child_handle);
    }
  }

  yoga_release_node(root_handle);
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

CAMLprim value opentui_raw_yoga_create(value unit_value) {
  CAMLparam1(unit_value);

  opentui_raw_yoga_tree_slot *tree;
  uint32_t tree_handle = yoga_allocate_tree(&tree);
  if (tree_handle == 0) {
    CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_NATIVE_FAILURE, 0));
  }

  tree->config = yogaConfigCreate();
  if (tree->config == NULL) {
    yoga_release_tree(tree_handle);
    CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_NATIVE_FAILURE, 0));
  }

  opentui_yoga_node_ref root = yogaNodeCreateWithConfig(tree->config);
  if (root == NULL) {
    yogaConfigFree(tree->config);
    yoga_release_tree(tree_handle);
    CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_NATIVE_FAILURE, 0));
  }

  opentui_raw_yoga_node_slot *root_slot;
  uint32_t root_handle = yoga_allocate_node(&root_slot, tree_handle);
  if (root_handle == 0) {
    yogaNodeFreeRecursive(root);
    yogaConfigFree(tree->config);
    yoga_release_tree(tree_handle);
    CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_NATIVE_FAILURE, 0));
  }

  root_slot->node = root;
  tree->root_handle = root_handle;
  CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_OK, tree_handle));
}

CAMLprim value opentui_raw_yoga_destroy(value tree_value) {
  CAMLparam1(tree_value);

  uint32_t tree_handle = (uint32_t)Int32_val(tree_value);
  opentui_raw_yoga_tree_slot *tree = yoga_tree_from_handle(tree_handle);
  if (tree == NULL) {
    CAMLreturn(Val_unit);
  }

  opentui_yoga_node_ref root = NULL;
  opentui_raw_yoga_node_slot *root_slot = yoga_node_from_handle(tree->root_handle);
  if (root_slot != NULL) {
    root = root_slot->node;
  }

  for (uint32_t index = 1; index < OPENTUI_RAW_YOGA_NODE_CAPACITY; index++) {
    opentui_raw_yoga_node_slot *node = &yoga_nodes[index];
    if (node->alive && node->tree_handle == tree_handle) {
      yoga_release_node(yoga_handle(index, node->generation));
    }
  }

  if (root != NULL) {
    yogaNodeFreeRecursive(root);
  }
  yogaConfigFree(tree->config);
  yoga_release_tree(tree_handle);
  CAMLreturn(Val_unit);
}

CAMLprim value opentui_raw_yoga_root(value tree_value) {
  CAMLparam1(tree_value);

  uint32_t tree_handle = (uint32_t)Int32_val(tree_value);
  opentui_raw_yoga_tree_slot *tree = yoga_tree_from_handle(tree_handle);
  if (tree == NULL) {
    CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_STALE_HANDLE, 0));
  }

  CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_OK, tree->root_handle));
}

CAMLprim value opentui_raw_yoga_add_child(value tree_value, value parent_value) {
  CAMLparam2(tree_value, parent_value);

  uint32_t tree_handle = (uint32_t)Int32_val(tree_value);
  uint32_t parent_handle = (uint32_t)Int32_val(parent_value);
  opentui_raw_yoga_tree_slot *tree = yoga_tree_from_handle(tree_handle);
  opentui_raw_yoga_node_slot *parent = yoga_node_from_handle(parent_handle);
  if (tree == NULL || parent == NULL) {
    CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_STALE_HANDLE, 0));
  }
  if (parent->tree_handle != tree_handle) {
    CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_INVALID_ARGUMENT, 0));
  }

  opentui_yoga_node_ref child = yogaNodeCreateWithConfig(tree->config);
  if (child == NULL) {
    CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_NATIVE_FAILURE, 0));
  }

  opentui_raw_yoga_node_slot *child_slot;
  uint32_t child_handle = yoga_allocate_node(&child_slot, tree_handle);
  if (child_handle == 0) {
    yogaNodeFreeRecursive(child);
    CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_NATIVE_FAILURE, 0));
  }

  uint32_t index = yogaNodeGetChildCount(parent->node);
  yogaNodeInsertChild(parent->node, child, index);
  child_slot->node = child;
  child_slot->parent_handle = parent_handle;
  CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_OK, child_handle));
}

CAMLprim value opentui_raw_yoga_remove_child(
    value tree_value,
    value parent_value,
    value child_value) {
  CAMLparam3(tree_value, parent_value, child_value);

  uint32_t tree_handle = (uint32_t)Int32_val(tree_value);
  uint32_t parent_handle = (uint32_t)Int32_val(parent_value);
  uint32_t child_handle = (uint32_t)Int32_val(child_value);
  opentui_raw_yoga_tree_slot *tree = yoga_tree_from_handle(tree_handle);
  opentui_raw_yoga_node_slot *parent = yoga_node_from_handle(parent_handle);
  opentui_raw_yoga_node_slot *child = yoga_node_from_handle(child_handle);
  if (tree == NULL || parent == NULL || child == NULL
      || parent->tree_handle != tree_handle
      || child->tree_handle != tree_handle
      || child->parent_handle != parent_handle) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  yogaNodeRemoveChild(parent->node, child->node);
  yogaNodeFreeRecursive(child->node);
  yoga_release_subtree_slots(tree_handle, child_handle);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_yoga_move_child(
    value tree_value,
    value parent_value,
    value child_value,
    value index_value) {
  CAMLparam4(tree_value, parent_value, child_value, index_value);

  int32_t signed_index = Int32_val(index_value);
  if (signed_index < 0) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  uint32_t tree_handle = (uint32_t)Int32_val(tree_value);
  uint32_t parent_handle = (uint32_t)Int32_val(parent_value);
  uint32_t child_handle = (uint32_t)Int32_val(child_value);
  uint32_t index = (uint32_t)signed_index;
  opentui_raw_yoga_tree_slot *tree = yoga_tree_from_handle(tree_handle);
  opentui_raw_yoga_node_slot *parent = yoga_node_from_handle(parent_handle);
  opentui_raw_yoga_node_slot *child = yoga_node_from_handle(child_handle);
  if (tree == NULL || parent == NULL || child == NULL
      || parent->tree_handle != tree_handle
      || child->tree_handle != tree_handle
      || child->parent_handle != parent_handle) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  uint32_t child_count = yogaNodeGetChildCount(parent->node);
  if (index >= child_count) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  yogaNodeRemoveChild(parent->node, child->node);
  yogaNodeInsertChild(parent->node, child->node, index);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

static int yoga_validate_dimension(value dimension_value, float *dimension) {
  double input = Double_val(dimension_value);
  if (!isfinite(input) || input < 0.0 || input > (double)FLT_MAX) {
    return OPENTUI_RAW_STATUS_INVALID_ARGUMENT;
  }

  *dimension = (float)input;
  return OPENTUI_RAW_STATUS_OK;
}

CAMLprim value opentui_raw_yoga_node_set_width(value node_value, value width_value) {
  CAMLparam2(node_value, width_value);

  uint32_t node_handle = (uint32_t)Int32_val(node_value);
  opentui_raw_yoga_node_slot *node = yoga_node_from_handle(node_handle);
  if (node == NULL) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }

  float width;
  int status = yoga_validate_dimension(width_value, &width);
  if (status != OPENTUI_RAW_STATUS_OK) {
    CAMLreturn(Val_int(status));
  }

  yogaNodeStyleSetValue(node->node, 0, 0, 1, width);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_yoga_node_set_height(value node_value, value height_value) {
  CAMLparam2(node_value, height_value);

  uint32_t node_handle = (uint32_t)Int32_val(node_value);
  opentui_raw_yoga_node_slot *node = yoga_node_from_handle(node_handle);
  if (node == NULL) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }

  float height;
  int status = yoga_validate_dimension(height_value, &height);
  if (status != OPENTUI_RAW_STATUS_OK) {
    CAMLreturn(Val_int(status));
  }

  yogaNodeStyleSetValue(node->node, 1, 0, 1, height);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_yoga_calculate(
    value tree_value,
    value width_value,
    value height_value,
    value direction_value) {
  CAMLparam4(tree_value, width_value, height_value, direction_value);

  uint32_t tree_handle = (uint32_t)Int32_val(tree_value);
  opentui_raw_yoga_tree_slot *tree = yoga_tree_from_handle(tree_handle);
  if (tree == NULL) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }

  float width = 0.0f;
  float height = 0.0f;
  int width_status = yoga_validate_dimension(width_value, &width);
  int height_status = yoga_validate_dimension(height_value, &height);
  int direction = Int_val(direction_value);
  if (width_status != OPENTUI_RAW_STATUS_OK
      || height_status != OPENTUI_RAW_STATUS_OK
      || direction < 0 || direction > 2) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  opentui_raw_yoga_node_slot *root = yoga_node_from_handle(tree->root_handle);
  if (root == NULL) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }

  yogaNodeCalculateLayout(root->node, width, height, (uint32_t)direction);
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_yoga_node_layout(value node_value) {
  CAMLparam1(node_value);

  uint32_t node_handle = (uint32_t)Int32_val(node_value);
  opentui_raw_yoga_node_slot *node = yoga_node_from_handle(node_handle);
  if (node == NULL) {
    CAMLreturn(make_status_layout(OPENTUI_RAW_STATUS_STALE_HANDLE, NULL));
  }

  opentui_external_yoga_layout layout;
  yogaNodeGetComputedLayout(node->node, &layout);
  CAMLreturn(make_status_layout(OPENTUI_RAW_STATUS_OK, &layout));
}
