#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#include "native/opentui_abi.h"
#include "raw_status.h"

#define OPENTUI_RAW_SPAN_FEED_CAPACITY 64
#define OPENTUI_RAW_SPAN_CAPACITY 4096
#define OPENTUI_RAW_RESERVATION_CAPACITY 64

typedef struct opentui_raw_span_feed_slot {
  uint16_t generation;
  bool alive;
  opentui_span_feed_ref stream;
  bool pending_span;
  uint32_t pending_span_handle;
  opentui_external_span_info pending_info;
  bool pending_reservation;
  uint32_t pending_reservation_handle;
} opentui_raw_span_feed_slot;

typedef struct opentui_raw_span_slot {
  uint16_t generation;
  bool alive;
  uint32_t feed_handle;
  opentui_external_span_info info;
} opentui_raw_span_slot;

typedef struct opentui_raw_reservation_slot {
  uint16_t generation;
  bool alive;
  uint32_t feed_handle;
  opentui_external_reserve_info info;
} opentui_raw_reservation_slot;

static opentui_raw_span_feed_slot span_feed_slots[OPENTUI_RAW_SPAN_FEED_CAPACITY];
static opentui_raw_span_slot span_slots[OPENTUI_RAW_SPAN_CAPACITY];
static opentui_raw_reservation_slot reservation_slots[OPENTUI_RAW_RESERVATION_CAPACITY];

static uint32_t make_token(uint32_t index, uint16_t generation) {
  return ((uint32_t)generation << 16) | index;
}

static uint32_t token_index(uint32_t token) {
  return token & UINT32_C(0xffff);
}

static uint16_t token_generation(uint32_t token) {
  return (uint16_t)(token >> 16);
}

static uint16_t next_generation(uint16_t generation) {
  return generation == UINT16_MAX ? 1 : (uint16_t)(generation + 1);
}

static int map_native_status(int32_t status) {
  switch (status) {
    case 0:
      return OPENTUI_RAW_STATUS_OK;
    case -1:
      return OPENTUI_RAW_STATUS_NO_SPACE;
    case -2:
      return OPENTUI_RAW_STATUS_MAX_BYTES;
    case -3:
      return OPENTUI_RAW_STATUS_INVALID_ARGUMENT;
    case -4:
      return OPENTUI_RAW_STATUS_NATIVE_FAILURE;
    case -5:
      return OPENTUI_RAW_STATUS_BUSY;
    default:
      return OPENTUI_RAW_STATUS_NATIVE_FAILURE;
  }
}

static opentui_raw_span_feed_slot *span_feed_from_token(
    uint32_t token,
    uint32_t *handle) {
  uint32_t index = token_index(token);
  if (index == 0 || index >= OPENTUI_RAW_SPAN_FEED_CAPACITY) {
    return NULL;
  }

  opentui_raw_span_feed_slot *slot = &span_feed_slots[index];
  if (!slot->alive || slot->generation != token_generation(token)) {
    return NULL;
  }

  if (handle != NULL) {
    *handle = token;
  }
  return slot;
}

static uint32_t span_feed_allocate(opentui_raw_span_feed_slot **output) {
  for (uint32_t index = 1; index < OPENTUI_RAW_SPAN_FEED_CAPACITY; index++) {
    opentui_raw_span_feed_slot *slot = &span_feed_slots[index];
    if (!slot->alive) {
      slot->generation = slot->generation == 0
          ? 1
          : next_generation(slot->generation);
      slot->alive = true;
      slot->stream = NULL;
      slot->pending_span = false;
      slot->pending_span_handle = 0;
      slot->pending_reservation = false;
      slot->pending_reservation_handle = 0;
      *output = slot;
      return make_token(index, slot->generation);
    }
  }

  return 0;
}

static opentui_raw_span_slot *span_from_token(uint32_t token) {
  uint32_t index = token_index(token);
  if (index == 0 || index >= OPENTUI_RAW_SPAN_CAPACITY) {
    return NULL;
  }

  opentui_raw_span_slot *slot = &span_slots[index];
  if (!slot->alive || slot->generation != token_generation(token)) {
    return NULL;
  }

  return slot;
}

static uint32_t span_allocate(
    uint32_t feed_handle,
    const opentui_external_span_info *info) {
  for (uint32_t index = 1; index < OPENTUI_RAW_SPAN_CAPACITY; index++) {
    opentui_raw_span_slot *slot = &span_slots[index];
    if (!slot->alive) {
      slot->generation = slot->generation == 0
          ? 1
          : next_generation(slot->generation);
      slot->alive = true;
      slot->feed_handle = feed_handle;
      slot->info = *info;
      return make_token(index, slot->generation);
    }
  }

  return 0;
}

static void span_release_slot(opentui_raw_span_slot *slot) {
  slot->alive = false;
  slot->feed_handle = 0;
}

static opentui_raw_reservation_slot *reservation_from_token(uint32_t token);
static void reservation_release_slot(opentui_raw_reservation_slot *slot);

static void cleanup_feed_pending(opentui_raw_span_feed_slot *feed) {
  if (feed->pending_span) {
    (void)streamMarkSpanConsumed(feed->stream, &feed->pending_info);
    if (feed->pending_span_handle != 0) {
      opentui_raw_span_slot *span = span_from_token(feed->pending_span_handle);
      if (span != NULL) {
        span_release_slot(span);
      }
    }
    feed->pending_span = false;
    feed->pending_span_handle = 0;
  }

  if (feed->pending_reservation) {
    (void)streamCancelReserved(feed->stream);
    if (feed->pending_reservation_handle != 0) {
      opentui_raw_reservation_slot *reservation = reservation_from_token(
          feed->pending_reservation_handle);
      if (reservation != NULL) {
        reservation_release_slot(reservation);
      }
    }
    feed->pending_reservation = false;
    feed->pending_reservation_handle = 0;
  }
}

static void clear_feed_pending_span(opentui_raw_span_feed_slot *feed) {
  feed->pending_span = false;
  feed->pending_span_handle = 0;
}

static void clear_feed_pending_reservation(opentui_raw_span_feed_slot *feed) {
  feed->pending_reservation = false;
  feed->pending_reservation_handle = 0;
}

static opentui_raw_reservation_slot *reservation_from_token(uint32_t token) {
  uint32_t index = token_index(token);
  if (index == 0 || index >= OPENTUI_RAW_RESERVATION_CAPACITY) {
    return NULL;
  }

  opentui_raw_reservation_slot *slot = &reservation_slots[index];
  if (!slot->alive || slot->generation != token_generation(token)) {
    return NULL;
  }

  return slot;
}

static uint32_t reservation_allocate(
    uint32_t feed_handle,
    const opentui_external_reserve_info *info) {
  for (uint32_t index = 1; index < OPENTUI_RAW_RESERVATION_CAPACITY; index++) {
    opentui_raw_reservation_slot *slot = &reservation_slots[index];
    if (!slot->alive) {
      slot->generation = slot->generation == 0
          ? 1
          : next_generation(slot->generation);
      slot->alive = true;
      slot->feed_handle = feed_handle;
      slot->info = *info;
      return make_token(index, slot->generation);
    }
  }

  return 0;
}

static void reservation_release_slot(opentui_raw_reservation_slot *slot) {
  slot->alive = false;
  slot->feed_handle = 0;
}

static bool read_options(
    value options_value,
    opentui_external_span_feed_options *options) {
  if (!Is_block(options_value) || Wosize_val(options_value) != 6) {
    return false;
  }

  int32_t chunk_size = Int32_val(Field(options_value, 0));
  int32_t initial_chunks = Int32_val(Field(options_value, 1));
  int64_t max_bytes = Int64_val(Field(options_value, 2));
  intnat growth_policy = Int_val(Field(options_value, 3));
  int32_t span_queue_capacity = Int32_val(Field(options_value, 5));
  if (chunk_size < 0 || initial_chunks < 0 || max_bytes < 0
      || span_queue_capacity < 0 || (growth_policy != 0 && growth_policy != 1)) {
    return false;
  }

  options->chunk_size = (uint32_t)chunk_size;
  options->initial_chunks = (uint32_t)initial_chunks;
  options->max_bytes = (uint64_t)max_bytes;
  options->growth_policy = (uint8_t)growth_policy;
  options->auto_commit_on_full = (uint8_t)Bool_val(Field(options_value, 4));
  options->span_queue_capacity = (uint32_t)span_queue_capacity;
  return true;
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

static value make_status_reservation(
    int status,
    uint32_t token,
    uint32_t capacity,
    value contents) {
  CAMLparam1(contents);
  CAMLlocalN(roots, 6);

  roots[0] = Val_int(status);
  if (status == OPENTUI_RAW_STATUS_OK) {
    roots[3] = caml_copy_int32((int32_t)token);
    roots[4] = caml_copy_int32((int32_t)capacity);
    roots[1] = caml_alloc_tuple(3);
    Store_field(roots[1], 0, roots[3]);
    Store_field(roots[1], 1, roots[4]);
    Store_field(roots[1], 2, contents);
    roots[2] = caml_alloc(1, 0);
    Store_field(roots[2], 0, roots[1]);
    roots[5] = caml_alloc_tuple(2);
    Store_field(roots[5], 0, roots[0]);
    Store_field(roots[5], 1, roots[2]);
  } else {
    roots[5] = caml_alloc_tuple(2);
    Store_field(roots[5], 0, roots[0]);
    Store_field(roots[5], 1, Val_none);
  }
  CAMLreturn(roots[5]);
}

static value make_status_stats(
    int status,
    const opentui_external_span_feed_stats *stats) {
  CAMLparam0();
  CAMLlocal4(result, status_value, stats_value, stats_option);

  status_value = Val_int(status);
  if (status == OPENTUI_RAW_STATUS_OK) {
    stats_value = caml_alloc_tuple(4);
    Store_field(stats_value, 0, caml_copy_int64((int64_t)stats->bytes_written));
    Store_field(stats_value, 1, caml_copy_int64((int64_t)stats->spans_committed));
    Store_field(stats_value, 2, caml_copy_int32((int32_t)stats->chunks));
    Store_field(stats_value, 3, caml_copy_int32((int32_t)stats->pending_spans));
    stats_option = caml_alloc(1, 0);
    Store_field(stats_option, 0, stats_value);
  } else {
    stats_option = Val_none;
  }

  result = caml_alloc_tuple(2);
  Store_field(result, 0, status_value);
  Store_field(result, 1, stats_option);
  CAMLreturn(result);
}

static value make_status_span(int status, value span_option) {
  CAMLparam1(span_option);
  CAMLlocal2(result, status_value);

  status_value = Val_int(status);
  result = caml_alloc_tuple(2);
  Store_field(result, 0, status_value);
  Store_field(result, 1, span_option);
  CAMLreturn(result);
}

static bool span_source(
    const opentui_external_span_info *info,
    const uint8_t **source) {
  if (info->len == 0) {
    *source = NULL;
    return true;
  }
  if (info->chunk_ptr == 0
      || (uintptr_t)info->offset > UINTPTR_MAX - info->chunk_ptr) {
    return false;
  }

  uintptr_t start = info->chunk_ptr + (uintptr_t)info->offset;
  if ((uintptr_t)info->len > UINTPTR_MAX - start) {
    return false;
  }

  *source = (const uint8_t *)start;
  return true;
}

static void invalidate_feed_spans(uint32_t feed_handle) {
  for (uint32_t index = 1; index < OPENTUI_RAW_SPAN_CAPACITY; index++) {
    opentui_raw_span_slot *slot = &span_slots[index];
    if (slot->alive && slot->feed_handle == feed_handle) {
      span_release_slot(slot);
    }
  }
}

static void release_feed_reservations(uint32_t feed_handle) {
  for (uint32_t index = 1; index < OPENTUI_RAW_RESERVATION_CAPACITY; index++) {
    opentui_raw_reservation_slot *slot = &reservation_slots[index];
    if (slot->alive && slot->feed_handle == feed_handle) {
      reservation_release_slot(slot);
    }
  }
}

CAMLprim value opentui_raw_span_feed_create(value options_value) {
  CAMLparam1(options_value);

  opentui_external_span_feed_options options;
  if (!read_options(options_value, &options)) {
    CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_INVALID_ARGUMENT, 0));
  }

  opentui_span_feed_ref stream = createNativeSpanFeed(&options);
  if (stream == NULL) {
    CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_NATIVE_FAILURE, 0));
  }

  opentui_raw_span_feed_slot *slot;
  uint32_t handle = span_feed_allocate(&slot);
  if (handle == 0) {
    destroyNativeSpanFeed(stream);
    CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_NATIVE_FAILURE, 0));
  }

  slot->stream = stream;
  int status = map_native_status(attachNativeSpanFeed(stream));
  if (status != OPENTUI_RAW_STATUS_OK) {
    destroyNativeSpanFeed(stream);
    slot->alive = false;
    slot->stream = NULL;
    CAMLreturn(make_status_handle(status, 0));
  }

  CAMLreturn(make_status_handle(OPENTUI_RAW_STATUS_OK, handle));
}

CAMLprim value opentui_raw_span_feed_close(value feed_value) {
  CAMLparam1(feed_value);

  uint32_t feed_handle;
  opentui_raw_span_feed_slot *slot = span_feed_from_token(
      (uint32_t)Int32_val(feed_value), &feed_handle);
  if (slot == NULL) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }

  cleanup_feed_pending(slot);
  int status = map_native_status(streamClose(slot->stream));
  if (status != OPENTUI_RAW_STATUS_OK) {
    CAMLreturn(Val_int(status));
  }

  invalidate_feed_spans(feed_handle);
  release_feed_reservations(feed_handle);
  destroyNativeSpanFeed(slot->stream);
  slot->alive = false;
  slot->stream = NULL;
  CAMLreturn(Val_int(OPENTUI_RAW_STATUS_OK));
}

CAMLprim value opentui_raw_span_feed_write(
    value feed_value,
    value data_value) {
  CAMLparam2(feed_value, data_value);

  opentui_raw_span_feed_slot *slot = span_feed_from_token(
      (uint32_t)Int32_val(feed_value), NULL);
  if (slot == NULL) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }

  cleanup_feed_pending(slot);
  mlsize_t data_length = caml_string_length(data_value);
  if ((uint64_t)data_length > UINT32_MAX) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  const uint8_t *source = data_length == 0
      ? NULL
      : (const uint8_t *)Bytes_val(data_value);
  CAMLreturn(Val_int(map_native_status(streamWrite(
      slot->stream,
      source,
      (uint32_t)data_length))));
}

CAMLprim value opentui_raw_span_feed_commit(value feed_value) {
  CAMLparam1(feed_value);

  opentui_raw_span_feed_slot *slot = span_feed_from_token(
      (uint32_t)Int32_val(feed_value), NULL);
  if (slot == NULL) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }

  cleanup_feed_pending(slot);
  CAMLreturn(Val_int(map_native_status(streamCommit(slot->stream))));
}

CAMLprim value opentui_raw_span_feed_reserve(
    value feed_value,
    value minimum_value) {
  CAMLparam2(feed_value, minimum_value);
  CAMLlocal2(result, contents);

  int32_t minimum_length = Int32_val(minimum_value);
  if (minimum_length < 0) {
    CAMLreturn(make_status_reservation(
        OPENTUI_RAW_STATUS_INVALID_ARGUMENT,
        0,
        0,
        Val_unit));
  }

  uint32_t feed_handle;
  opentui_raw_span_feed_slot *feed = span_feed_from_token(
      (uint32_t)Int32_val(feed_value), &feed_handle);
  if (feed == NULL) {
    CAMLreturn(make_status_reservation(
        OPENTUI_RAW_STATUS_STALE_HANDLE,
        0,
        0,
        Val_unit));
  }

  cleanup_feed_pending(feed);
  opentui_external_reserve_info info;
  int status = map_native_status(streamReserve(
      feed->stream,
      (uint32_t)minimum_length,
      &info));
  if (status != OPENTUI_RAW_STATUS_OK) {
    CAMLreturn(make_status_reservation(status, 0, 0, Val_unit));
  }

  feed->pending_reservation = true;
  feed->pending_reservation_handle = 0;
  uint32_t reservation_handle = reservation_allocate(feed_handle, &info);
  if (reservation_handle == 0) {
    cleanup_feed_pending(feed);
    result = make_status_reservation(
        OPENTUI_RAW_STATUS_NATIVE_FAILURE,
        0,
        0,
        Val_unit);
    CAMLreturn(result);
  }
  feed->pending_reservation_handle = reservation_handle;

  contents = caml_alloc_string((mlsize_t)info.len);
  result = make_status_reservation(
      OPENTUI_RAW_STATUS_OK,
      reservation_handle,
      info.len,
      contents);
  clear_feed_pending_reservation(feed);
  CAMLreturn(result);
}

CAMLprim value opentui_raw_span_feed_reservation_commit(
    value reservation_value,
    value data_value,
    value used_value) {
  CAMLparam3(reservation_value, data_value, used_value);

  opentui_raw_reservation_slot *reservation = reservation_from_token(
      (uint32_t)Int32_val(reservation_value));
  if (reservation == NULL) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }

  int32_t used = Int32_val(used_value);
  mlsize_t data_length = caml_string_length(data_value);
  if (used < 0 || (uint32_t)used > reservation->info.len
      || (uint64_t)data_length < (uint64_t)used) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_INVALID_ARGUMENT));
  }

  uint32_t feed_handle = reservation->feed_handle;
  uint32_t feed_index = token_index(feed_handle);
  if (feed_index == 0 || feed_index >= OPENTUI_RAW_SPAN_FEED_CAPACITY) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  opentui_raw_span_feed_slot *feed = &span_feed_slots[feed_index];
  if (!feed->alive || feed->generation != token_generation(feed_handle)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }

  cleanup_feed_pending(feed);
  if (used != 0) {
    if (reservation->info.ptr == 0) {
      CAMLreturn(Val_int(OPENTUI_RAW_STATUS_NATIVE_FAILURE));
    }
    memcpy(
        (void *)(uintptr_t)reservation->info.ptr,
        Bytes_val(data_value),
        (size_t)used);
  }

  int status = map_native_status(streamCommitReserved(
      feed->stream,
      (uint32_t)used));
  if (status == OPENTUI_RAW_STATUS_OK) {
    reservation_release_slot(reservation);
  }
  CAMLreturn(Val_int(status));
}

CAMLprim value opentui_raw_span_feed_reservation_cancel(
    value reservation_value) {
  CAMLparam1(reservation_value);

  opentui_raw_reservation_slot *reservation = reservation_from_token(
      (uint32_t)Int32_val(reservation_value));
  if (reservation == NULL) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }

  uint32_t feed_handle = reservation->feed_handle;
  uint32_t feed_index = token_index(feed_handle);
  if (feed_index == 0 || feed_index >= OPENTUI_RAW_SPAN_FEED_CAPACITY) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  opentui_raw_span_feed_slot *feed = &span_feed_slots[feed_index];
  if (!feed->alive || feed->generation != token_generation(feed_handle)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }

  cleanup_feed_pending(feed);
  int status = map_native_status(streamCancelReserved(feed->stream));
  if (status == OPENTUI_RAW_STATUS_OK) {
    reservation_release_slot(reservation);
  }
  CAMLreturn(Val_int(status));
}

CAMLprim value opentui_raw_span_feed_stats(value feed_value) {
  CAMLparam1(feed_value);

  opentui_raw_span_feed_slot *feed = span_feed_from_token(
      (uint32_t)Int32_val(feed_value), NULL);
  if (feed == NULL) {
    CAMLreturn(make_status_stats(OPENTUI_RAW_STATUS_STALE_HANDLE, NULL));
  }

  cleanup_feed_pending(feed);
  opentui_external_span_feed_stats stats;
  int status = map_native_status(streamGetStats(feed->stream, &stats));
  CAMLreturn(make_status_stats(status, status == OPENTUI_RAW_STATUS_OK ? &stats : NULL));
}

CAMLprim value opentui_raw_span_feed_drain(value feed_value) {
  CAMLparam1(feed_value);
  CAMLlocalN(roots, 5);

  opentui_raw_span_feed_slot *feed = span_feed_from_token(
      (uint32_t)Int32_val(feed_value), NULL);
  if (feed == NULL) {
    CAMLreturn(make_status_span(OPENTUI_RAW_STATUS_STALE_HANDLE, Val_none));
  }

  cleanup_feed_pending(feed);
  opentui_external_span_info info;
  uint32_t count = streamDrainSpans(feed->stream, &info, 1);
  if (count == 0) {
    CAMLreturn(make_status_span(OPENTUI_RAW_STATUS_OK, Val_none));
  }

  feed->pending_span = true;
  feed->pending_span_handle = 0;
  feed->pending_info = info;

  const uint8_t *source;
  if (!span_source(&info, &source)) {
    cleanup_feed_pending(feed);
    CAMLreturn(make_status_span(OPENTUI_RAW_STATUS_NATIVE_FAILURE, Val_none));
  }

  uint32_t span_handle = span_allocate(
      (uint32_t)Int32_val(feed_value),
      &info);
  if (span_handle == 0) {
    cleanup_feed_pending(feed);
    CAMLreturn(make_status_span(OPENTUI_RAW_STATUS_NATIVE_FAILURE, Val_none));
  }
  feed->pending_span_handle = span_handle;

  roots[0] = caml_alloc_string((mlsize_t)info.len);
  if (info.len != 0) {
    memcpy(Bytes_val(roots[0]), source, info.len);
  }
  roots[1] = caml_copy_int32((int32_t)span_handle);
  roots[2] = caml_alloc_tuple(2);
  Store_field(roots[2], 0, roots[0]);
  Store_field(roots[2], 1, roots[1]);
  roots[3] = caml_alloc(1, 0);
  Store_field(roots[3], 0, roots[2]);
  roots[4] = caml_alloc_tuple(2);
  Store_field(roots[4], 0, Val_int(OPENTUI_RAW_STATUS_OK));
  Store_field(roots[4], 1, roots[3]);
  clear_feed_pending_span(feed);
  CAMLreturn(roots[4]);
}

CAMLprim value opentui_raw_span_release(value span_value) {
  CAMLparam1(span_value);

  opentui_raw_span_slot *span = span_from_token(
      (uint32_t)Int32_val(span_value));
  if (span == NULL) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }

  uint32_t feed_handle = span->feed_handle;
  uint32_t feed_index = token_index(feed_handle);
  if (feed_index == 0 || feed_index >= OPENTUI_RAW_SPAN_FEED_CAPACITY) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }
  opentui_raw_span_feed_slot *feed = &span_feed_slots[feed_index];
  if (!feed->alive || feed->generation != token_generation(feed_handle)) {
    CAMLreturn(Val_int(OPENTUI_RAW_STATUS_STALE_HANDLE));
  }

  cleanup_feed_pending(feed);
  int status = map_native_status(streamMarkSpanConsumed(
      feed->stream,
      &span->info));
  if (status == OPENTUI_RAW_STATUS_OK) {
    span_release_slot(span);
  }
  CAMLreturn(Val_int(status));
}
