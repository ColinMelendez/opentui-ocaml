#include <caml/alloc.h>
#include <caml/bigarray.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#include <pthread.h>
#include <stdio.h>
#include <time.h>
#include <unistd.h>
#include <stdint.h>
#include <string.h>

#include <webgpu.h>
#include <wgpu.h>

/* Blocking request pattern: every asynchronous operation in this file is
   registered with WGPUCallbackMode_WaitAnyOnly, which fires the callback
   exclusively inside wgpuInstanceWaitAny on the calling thread. The OCaml
   side therefore observes fully synchronous, single-threaded calls and no
   callback ever enters OCaml from a foreign thread. */

#define OPENTUI_WGPU_WAIT_FAILURE -1
#define Wgpu_align4_size(n) (((n) + 3) / 4 * 4)

/* Bounded enough to fail loud, generous enough for slow software adapters. */
#define OPENTUI_WGPU_MAP_TIMEOUT_SECONDS 10.0

typedef struct {
  int done;
  int32_t status;
  uint64_t handle;
  char message[256];
} opentui_wgpu_wait;

static WGPUStringView opentui_wgpu_label(const char *text) {
  /* wgpu-native v29.0.1.1 misparses descriptors whose WGPUStringView fields
     are {NULL, 0}: the validation layer then observes garbage in the next
     field (for example TextureUsages(0x0)). Every descriptor therefore
     carries a real label. */
  return (WGPUStringView){text, strlen(text)};
}

static void opentui_wgpu_copy_message(
    char *destination,
    size_t destination_size,
    WGPUStringView message);

/* ---- diagnostics capture (risk 16b) ------------------------------------
   Uncaptured GPU errors, device loss, and wgpu-native log lines land in
   fixed buffers guarded by one mutex; OCaml drains them between frames.
   Callbacks may fire on wgpu-owned threads, so no OCaml value is ever
   touched here. */
#define OPENTUI_WGPU_DIAG_SLOTS 256
#define OPENTUI_WGPU_DIAG_LINE 256

static pthread_mutex_t opentui_wgpu_diag_mutex = PTHREAD_MUTEX_INITIALIZER;
static char opentui_wgpu_diag_lines[OPENTUI_WGPU_DIAG_SLOTS][OPENTUI_WGPU_DIAG_LINE];
static int opentui_wgpu_diag_head = 0;
static int opentui_wgpu_diag_count = 0;

static void opentui_wgpu_diag_push(const char *text) {
  pthread_mutex_lock(&opentui_wgpu_diag_mutex);
  snprintf(opentui_wgpu_diag_lines[opentui_wgpu_diag_head],
           OPENTUI_WGPU_DIAG_LINE, "%s", text);
  opentui_wgpu_diag_head =
      (opentui_wgpu_diag_head + 1) % OPENTUI_WGPU_DIAG_SLOTS;
  if (opentui_wgpu_diag_count < OPENTUI_WGPU_DIAG_SLOTS) {
    opentui_wgpu_diag_count++;
  }
  pthread_mutex_unlock(&opentui_wgpu_diag_mutex);
}

static void opentui_wgpu_uncaptured_error(
    const WGPUDevice *device,
    WGPUErrorType type,
    WGPUStringView message,
    void *userdata1,
    void *userdata2) {
  (void)device;
  (void)userdata1;
  (void)userdata2;
  char line[OPENTUI_WGPU_DIAG_LINE];
  char message_text[OPENTUI_WGPU_DIAG_LINE - 32];
  opentui_wgpu_copy_message(message_text, sizeof message_text, message);
  snprintf(line, sizeof line, "uncaptured gpu error (type %d): %s", (int)type,
           message_text);
  opentui_wgpu_diag_push(line);
}

static void opentui_wgpu_log_callback(WGPULogLevel level,
                                      WGPUStringView message,
                                      void *userdata) {
  (void)userdata;
  char line[OPENTUI_WGPU_DIAG_LINE];
  char message_text[OPENTUI_WGPU_DIAG_LINE - 32];
  opentui_wgpu_copy_message(message_text, sizeof message_text, message);
  snprintf(line, sizeof line, "wgpu[%d]: %s", (int)level, message_text);
  opentui_wgpu_diag_push(line);
}

CAMLprim value opentui_wgpu_enable_diagnostics(value unit) {
  CAMLparam1(unit);
  (void)unit;
  wgpuSetLogCallback(opentui_wgpu_log_callback, NULL);
  wgpuSetLogLevel(WGPULogLevel_Warn);
  CAMLreturn(Val_unit);
}

/* Drains up to [max] captured diagnostic lines into a fresh OCaml list. */
CAMLprim value opentui_wgpu_drain_diagnostics(value max_value) {
  CAMLparam1(max_value);
  int remaining = Int_val(max_value);
  value list = Val_int(0);
  char drained[OPENTUI_WGPU_DIAG_SLOTS][OPENTUI_WGPU_DIAG_LINE];
  int count = 0;
  pthread_mutex_lock(&opentui_wgpu_diag_mutex);
  while (count < opentui_wgpu_diag_count && remaining > 0) {
    int index =
        (opentui_wgpu_diag_head - opentui_wgpu_diag_count + count +
         OPENTUI_WGPU_DIAG_SLOTS) % OPENTUI_WGPU_DIAG_SLOTS;
    memcpy(drained[count], opentui_wgpu_diag_lines[index],
           OPENTUI_WGPU_DIAG_LINE);
    count++;
    remaining--;
  }
  if (count == opentui_wgpu_diag_count) {
    opentui_wgpu_diag_head = 0;
    opentui_wgpu_diag_count = 0;
  } else {
    opentui_wgpu_diag_count -= count;
  }
  pthread_mutex_unlock(&opentui_wgpu_diag_mutex);
  for (int i = count - 1; i >= 0; i--) {
    value cell = caml_alloc_tuple(2);
    Store_field(cell, 0, caml_copy_string(drained[i]));
    Store_field(cell, 1, list);
    list = cell;
  }
  CAMLreturn(list);
}

static void opentui_wgpu_copy_message(
    char *destination,
    size_t destination_size,
    WGPUStringView message) {
  if (message.data == NULL || message.length == 0) {
    destination[0] = '\0';
    return;
  }
  size_t length = message.length;
  if (length == SIZE_MAX) {
    /* Null-terminated sentinel: measure instead of trusting the length. */
    length = strlen(message.data);
  }
  if (length >= destination_size) {
    length = destination_size - 1;
  }
  memcpy(destination, message.data, length);
  destination[length] = '\0';
}

static value opentui_wgpu_make_result(
    int32_t status,
    uint64_t handle,
    const char *message) {
  CAMLparam0();
  CAMLlocal2(result, message_value);

  message_value = caml_copy_string(message);
  result = caml_alloc_tuple(3);
  Store_field(result, 0, Val_int(status));
  Store_field(result, 1, caml_copy_int64((int64_t)handle));
  Store_field(result, 2, message_value);
  CAMLreturn(result);
}

static value opentui_wgpu_make_handle_pair(int succeeded, uint64_t handle) {
  CAMLparam0();
  CAMLlocal1(result);

  result = caml_alloc_tuple(2);
  Store_field(result, 0, Val_bool(succeeded != 0));
  Store_field(result, 1, caml_copy_int64((int64_t)handle));
  CAMLreturn(result);
}

static void opentui_wgpu_wait_for(
    opentui_wgpu_wait *wait,
    WGPUInstance instance,
    WGPUFuture future) {
  WGPUFutureWaitInfo wait_info;
  wait_info.future = future;
  wait_info.completed = WGPU_FALSE;
  while (wait->done == 0) {
    WGPUWaitStatus status =
        wgpuInstanceWaitAny(instance, 1, &wait_info, UINT64_MAX);
    if (status == WGPUWaitStatus_Error) {
      break;
    }
  }
  if (wait->done == 0) {
    wait->status = OPENTUI_WGPU_WAIT_FAILURE;
    wait->handle = 0;
    snprintf(
        wait->message,
        sizeof wait->message,
        "wgpuInstanceWaitAny returned without completing the operation");
  }
}

static void opentui_wgpu_adapter_callback(
    WGPURequestAdapterStatus status,
    WGPUAdapter adapter,
    WGPUStringView message,
    void *userdata1,
    void *userdata2) {
  (void)userdata2;
  opentui_wgpu_wait *wait = (opentui_wgpu_wait *)userdata1;
  wait->done = 1;
  wait->status = (int32_t)status;
  wait->handle = (uint64_t)(uintptr_t)adapter;
  opentui_wgpu_copy_message(wait->message, sizeof wait->message, message);
}

static void opentui_wgpu_device_callback(
    WGPURequestDeviceStatus status,
    WGPUDevice device,
    WGPUStringView message,
    void *userdata1,
    void *userdata2) {
  (void)userdata2;
  opentui_wgpu_wait *wait = (opentui_wgpu_wait *)userdata1;
  wait->done = 1;
  wait->status = (int32_t)status;
  wait->handle = (uint64_t)(uintptr_t)device;
  opentui_wgpu_copy_message(wait->message, sizeof wait->message, message);
}

static void opentui_wgpu_buffer_map_callback(
    WGPUMapAsyncStatus status,
    WGPUStringView message,
    void *userdata1,
    void *userdata2) {
  (void)userdata2;
  opentui_wgpu_wait *wait = (opentui_wgpu_wait *)userdata1;
  wait->done = 1;
  wait->status = (int32_t)status;
  wait->handle = 0;
  opentui_wgpu_copy_message(wait->message, sizeof wait->message, message);
}

CAMLprim value opentui_wgpu_instance_create(value unit) {
  CAMLparam1(unit);
  (void)unit;
  WGPUInstanceDescriptor descriptor;
  memset(&descriptor, 0, sizeof descriptor);
  WGPUInstance instance = wgpuCreateInstance(&descriptor);
  CAMLreturn(opentui_wgpu_make_handle_pair(
      instance != NULL,
      (uint64_t)(uintptr_t)instance));
}

CAMLprim value opentui_wgpu_instance_release(value instance) {
  CAMLparam1(instance);
  wgpuInstanceRelease((WGPUInstance)(uintptr_t)Int64_val(instance));
  CAMLreturn(Val_unit);
}

CAMLprim value opentui_wgpu_instance_request_adapter(value instance_value) {
  CAMLparam1(instance_value);
  WGPUInstance instance = (WGPUInstance)(uintptr_t)Int64_val(instance_value);

  opentui_wgpu_wait wait;
  memset(&wait, 0, sizeof wait);

  WGPURequestAdapterCallbackInfo info;
  memset(&info, 0, sizeof info);
  info.mode = WGPUCallbackMode_WaitAnyOnly;
  info.callback = opentui_wgpu_adapter_callback;
  info.userdata1 = &wait;
  info.userdata2 = NULL;

  WGPURequestAdapterOptions options;
  memset(&options, 0, sizeof options);

  WGPUFuture future = wgpuInstanceRequestAdapter(instance, &options, info);
  opentui_wgpu_wait_for(&wait, instance, future);
  CAMLreturn(opentui_wgpu_make_result(wait.status, wait.handle, wait.message));
}

CAMLprim value opentui_wgpu_adapter_release(value adapter) {
  CAMLparam1(adapter);
  wgpuAdapterRelease((WGPUAdapter)(uintptr_t)Int64_val(adapter));
  CAMLreturn(Val_unit);
}

CAMLprim value opentui_wgpu_adapter_request_device(
    value instance_value,
    value adapter_value) {
  CAMLparam2(instance_value, adapter_value);
  WGPUInstance instance = (WGPUInstance)(uintptr_t)Int64_val(instance_value);
  WGPUAdapter adapter = (WGPUAdapter)(uintptr_t)Int64_val(adapter_value);

  opentui_wgpu_wait wait;
  memset(&wait, 0, sizeof wait);

  WGPURequestDeviceCallbackInfo info;
  memset(&info, 0, sizeof info);
  info.mode = WGPUCallbackMode_WaitAnyOnly;
  info.callback = opentui_wgpu_device_callback;
  info.userdata1 = &wait;
  info.userdata2 = NULL;

  WGPUDeviceDescriptor descriptor;
  memset(&descriptor, 0, sizeof descriptor);
  descriptor.uncapturedErrorCallbackInfo.callback =
      opentui_wgpu_uncaptured_error;

  WGPUFuture future = wgpuAdapterRequestDevice(adapter, &descriptor, info);
  opentui_wgpu_wait_for(&wait, instance, future);
  CAMLreturn(opentui_wgpu_make_result(wait.status, wait.handle, wait.message));
}

CAMLprim value opentui_wgpu_device_release(value device) {
  CAMLparam1(device);
  wgpuDeviceRelease((WGPUDevice)(uintptr_t)Int64_val(device));
  CAMLreturn(Val_unit);
}

CAMLprim value opentui_wgpu_device_get_queue(value device) {
  CAMLparam1(device);
  WGPUQueue queue =
      wgpuDeviceGetQueue((WGPUDevice)(uintptr_t)Int64_val(device));
  CAMLreturn(caml_copy_int64((int64_t)(uintptr_t)queue));
}

CAMLprim value opentui_wgpu_queue_release(value queue) {
  CAMLparam1(queue);
  wgpuQueueRelease((WGPUQueue)(uintptr_t)Int64_val(queue));
  CAMLreturn(Val_unit);
}

CAMLprim value opentui_wgpu_device_create_texture(value device_value, value options) {
  CAMLparam2(device_value, options);
  WGPUDevice device = (WGPUDevice)(uintptr_t)Int64_val(device_value);

  uint32_t width = (uint32_t)Long_val(Field(options, 0));
  uint32_t height = (uint32_t)Long_val(Field(options, 1));

  WGPUTextureDescriptor descriptor;
  memset(&descriptor, 0, sizeof descriptor);
  descriptor.label = opentui_wgpu_label("opentui-wgpu-render-target");
  descriptor.usage = (WGPUTextureUsage)Int64_val(Field(options, 3));
  descriptor.dimension = WGPUTextureDimension_2D;
  descriptor.size.width = width;
  descriptor.size.height = height;
  descriptor.size.depthOrArrayLayers = 1;
  descriptor.format = (WGPUTextureFormat)Long_val(Field(options, 2));
  descriptor.mipLevelCount = 1;
  descriptor.sampleCount = 1;

  WGPUTexture texture = wgpuDeviceCreateTexture(device, &descriptor);
  CAMLreturn(opentui_wgpu_make_handle_pair(
      texture != NULL,
      (uint64_t)(uintptr_t)texture));
}

CAMLprim value opentui_wgpu_texture_release(value texture) {
  CAMLparam1(texture);
  wgpuTextureRelease((WGPUTexture)(uintptr_t)Int64_val(texture));
  CAMLreturn(Val_unit);
}

CAMLprim value opentui_wgpu_texture_create_view(value texture_value) {
  CAMLparam1(texture_value);
  WGPUTexture texture = (WGPUTexture)(uintptr_t)Int64_val(texture_value);
  WGPUTextureView view = wgpuTextureCreateView(texture, NULL);
  CAMLreturn(opentui_wgpu_make_handle_pair(
      view != NULL,
      (uint64_t)(uintptr_t)view));
}

CAMLprim value opentui_wgpu_texture_view_release(value view) {
  CAMLparam1(view);
  wgpuTextureViewRelease((WGPUTextureView)(uintptr_t)Int64_val(view));
  CAMLreturn(Val_unit);
}

CAMLprim value opentui_wgpu_device_create_buffer(value device_value, value options) {
  CAMLparam2(device_value, options);
  WGPUDevice device = (WGPUDevice)(uintptr_t)Int64_val(device_value);

  WGPUBufferDescriptor descriptor;
  memset(&descriptor, 0, sizeof descriptor);
  descriptor.label = opentui_wgpu_label("opentui-wgpu-readback");
  descriptor.usage = (WGPUBufferUsage)Int64_val(Field(options, 1));
  descriptor.size = (uint64_t)Int64_val(Field(options, 0));
  descriptor.mappedAtCreation = WGPU_FALSE;

  WGPUBuffer buffer = wgpuDeviceCreateBuffer(device, &descriptor);
  CAMLreturn(opentui_wgpu_make_handle_pair(
      buffer != NULL,
      (uint64_t)(uintptr_t)buffer));
}

CAMLprim value opentui_wgpu_buffer_release(value buffer) {
  CAMLparam1(buffer);
  wgpuBufferRelease((WGPUBuffer)(uintptr_t)Int64_val(buffer));
  CAMLreturn(Val_unit);
}

CAMLprim value opentui_wgpu_device_create_command_encoder(value device_value) {
  CAMLparam1(device_value);
  WGPUDevice device = (WGPUDevice)(uintptr_t)Int64_val(device_value);

  WGPUCommandEncoderDescriptor descriptor;
  memset(&descriptor, 0, sizeof descriptor);
  descriptor.label = opentui_wgpu_label("opentui-wgpu-frame-encoder");

  WGPUCommandEncoder encoder =
      wgpuDeviceCreateCommandEncoder(device, &descriptor);
  CAMLreturn(opentui_wgpu_make_handle_pair(
      encoder != NULL,
      (uint64_t)(uintptr_t)encoder));
}

CAMLprim value opentui_wgpu_command_encoder_release(value encoder) {
  CAMLparam1(encoder);
  wgpuCommandEncoderRelease((WGPUCommandEncoder)(uintptr_t)Int64_val(encoder));
  CAMLreturn(Val_unit);
}

CAMLprim value opentui_wgpu_encoder_begin_render_pass_clear(
    value encoder_value,
    value view_value,
    value clear_color) {
  CAMLparam3(encoder_value, view_value, clear_color);
  WGPUCommandEncoder encoder =
      (WGPUCommandEncoder)(uintptr_t)Int64_val(encoder_value);
  WGPUTextureView view = (WGPUTextureView)(uintptr_t)Int64_val(view_value);

  WGPURenderPassColorAttachment attachment;
  memset(&attachment, 0, sizeof attachment);
  attachment.view = view;
  attachment.depthSlice = WGPU_DEPTH_SLICE_UNDEFINED;
  attachment.resolveTarget = NULL;
  attachment.loadOp = WGPULoadOp_Clear;
  attachment.storeOp = WGPUStoreOp_Store;
  attachment.clearValue.r = Double_val(Field(clear_color, 0));
  attachment.clearValue.g = Double_val(Field(clear_color, 1));
  attachment.clearValue.b = Double_val(Field(clear_color, 2));
  attachment.clearValue.a = Double_val(Field(clear_color, 3));

  WGPURenderPassDescriptor descriptor;
  memset(&descriptor, 0, sizeof descriptor);
  descriptor.label = opentui_wgpu_label("opentui-wgpu-clear-pass");
  descriptor.colorAttachmentCount = 1;
  descriptor.colorAttachments = &attachment;

  WGPURenderPassEncoder pass =
      wgpuCommandEncoderBeginRenderPass(encoder, &descriptor);
  wgpuRenderPassEncoderEnd(pass);
  wgpuRenderPassEncoderRelease(pass);
  CAMLreturn(Val_unit);
}

CAMLprim value opentui_wgpu_encoder_copy_texture_to_buffer(
    value encoder_value,
    value texture_value,
    value buffer_value,
    value copy_region) {
  CAMLparam4(encoder_value, texture_value, buffer_value, copy_region);
  WGPUCommandEncoder encoder =
      (WGPUCommandEncoder)(uintptr_t)Int64_val(encoder_value);
  WGPUTexture texture = (WGPUTexture)(uintptr_t)Int64_val(texture_value);
  WGPUBuffer buffer = (WGPUBuffer)(uintptr_t)Int64_val(buffer_value);

  uint32_t height = (uint32_t)Long_val(Field(copy_region, 1));

  WGPUTexelCopyTextureInfo source;
  memset(&source, 0, sizeof source);
  source.texture = texture;
  source.aspect = WGPUTextureAspect_All;

  WGPUTexelCopyBufferLayout layout;
  memset(&layout, 0, sizeof layout);
  layout.bytesPerRow = (uint32_t)Long_val(Field(copy_region, 2));
  layout.rowsPerImage = height;

  WGPUTexelCopyBufferInfo destination;
  memset(&destination, 0, sizeof destination);
  destination.layout = layout;
  destination.buffer = buffer;

  WGPUExtent3D copy_size;
  copy_size.width = (uint32_t)Long_val(Field(copy_region, 0));
  copy_size.height = height;
  copy_size.depthOrArrayLayers = 1;

  wgpuCommandEncoderCopyTextureToBuffer(
      encoder,
      &source,
      &destination,
      &copy_size);
  CAMLreturn(Val_unit);
}

CAMLprim value opentui_wgpu_command_encoder_finish(value encoder_value) {
  CAMLparam1(encoder_value);
  WGPUCommandEncoder encoder =
      (WGPUCommandEncoder)(uintptr_t)Int64_val(encoder_value);
  WGPUCommandBuffer command_buffer = wgpuCommandEncoderFinish(encoder, NULL);
  CAMLreturn(opentui_wgpu_make_handle_pair(
      command_buffer != NULL,
      (uint64_t)(uintptr_t)command_buffer));
}

CAMLprim value opentui_wgpu_command_buffer_release(value command_buffer) {
  CAMLparam1(command_buffer);
  wgpuCommandBufferRelease((WGPUCommandBuffer)(uintptr_t)Int64_val(command_buffer));
  CAMLreturn(Val_unit);
}

CAMLprim value opentui_wgpu_queue_submit_one(value queue_value, value command) {
  CAMLparam2(queue_value, command);
  WGPUQueue queue = (WGPUQueue)(uintptr_t)Int64_val(queue_value);
  WGPUCommandBuffer command_buffer =
      (WGPUCommandBuffer)(uintptr_t)Int64_val(command);
  wgpuQueueSubmit(queue, 1, &command_buffer);
  CAMLreturn(Val_unit);
}

CAMLprim value opentui_wgpu_buffer_map_read_blocking(
    value device_value,
    value buffer_value,
    value size) {
  CAMLparam3(device_value, buffer_value, size);
  WGPUDevice device = (WGPUDevice)(uintptr_t)Int64_val(device_value);
  WGPUBuffer buffer = (WGPUBuffer)(uintptr_t)Int64_val(buffer_value);

  /* Buffer map completion is not wired into the futures API in
     wgpu-native v29.0.1.1 (map callbacks registered through either wait-any
     mode panic as not implemented). The wgpu.h device-poll extension drives
     the callback on the calling thread instead; WaitAnyOnly mode keeps the
     callback forbidden everywhere except our own poll calls, so completion
     stays single-threaded by construction. */
  opentui_wgpu_wait wait;
  memset(&wait, 0, sizeof wait);

  WGPUBufferMapCallbackInfo info;
  memset(&info, 0, sizeof info);
  info.mode = WGPUCallbackMode_WaitAnyOnly;
  info.callback = opentui_wgpu_buffer_map_callback;
  info.userdata1 = &wait;
  info.userdata2 = NULL;

  wgpuBufferMapAsync(buffer, WGPUMapMode_Read, 0, (size_t)Int64_val(size), info);

  /* Pump completion without blocking so a backend that never finishes (a
     broken software adapter, a lost device that suppresses callbacks) turns
     into a structured timeout instead of an unkillable wait. Blocking poll
     calls cannot implement that bound because they only return when some
     work completes. */
  struct timespec start;
  clock_gettime(CLOCK_MONOTONIC, &start);
  while (wait.done == 0) {
    wgpuDevicePoll(device, WGPU_FALSE, NULL);
    if (wait.done != 0) {
      break;
    }
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    double elapsed =
        (double)(now.tv_sec - start.tv_sec)
        + (double)(now.tv_nsec - start.tv_nsec) / 1e9;
    if (elapsed >= OPENTUI_WGPU_MAP_TIMEOUT_SECONDS) {
      wait.status = OPENTUI_WGPU_WAIT_FAILURE;
      snprintf(
          wait.message,
          sizeof wait.message,
          "buffer map timed out after %.1f seconds",
          elapsed);
      break;
    }
    usleep(1000);
  }
  CAMLreturn(opentui_wgpu_make_result(wait.status, 0, wait.message));
}

CAMLprim value opentui_wgpu_buffer_get_mapped_range_copy(
    value buffer_value,
    value offset,
    value size,
    value destination) {
  CAMLparam4(buffer_value, offset, size, destination);
  WGPUBuffer buffer = (WGPUBuffer)(uintptr_t)Int64_val(buffer_value);

  struct caml_ba_array *array = Caml_ba_array_val(destination);
  if (Int64_val(size) > (int64_t)array->dim[0]) {
    CAMLreturn(Val_int(0));
  }

  void *mapped = wgpuBufferGetMappedRange(
      buffer,
      (size_t)Int64_val(offset),
      (size_t)Int64_val(size));
  if (mapped == NULL) {
    CAMLreturn(Val_int(0));
  }
  memcpy(Caml_ba_data_val(destination), mapped, (size_t)Int64_val(size));
  CAMLreturn(Val_int(1));
}

CAMLprim value opentui_wgpu_buffer_unmap(value buffer) {
  CAMLparam1(buffer);
  wgpuBufferUnmap((WGPUBuffer)(uintptr_t)Int64_val(buffer));
  CAMLreturn(Val_unit);
}

CAMLprim value opentui_wgpu_texture_format_rgba8_unorm(value unit) {
  CAMLparam1(unit);
  (void)unit;
  CAMLreturn(Val_long(WGPUTextureFormat_RGBA8Unorm));
}

CAMLprim value opentui_wgpu_texture_usage_render_attachment(value unit) {
  CAMLparam1(unit);
  (void)unit;
  CAMLreturn(caml_copy_int64((int64_t)WGPUTextureUsage_RenderAttachment));
}

CAMLprim value opentui_wgpu_texture_usage_copy_source(value unit) {
  CAMLparam1(unit);
  (void)unit;
  CAMLreturn(caml_copy_int64((int64_t)WGPUTextureUsage_CopySrc));
}

CAMLprim value opentui_wgpu_buffer_usage_map_read(value unit) {
  CAMLparam1(unit);
  (void)unit;
  CAMLreturn(caml_copy_int64((int64_t)WGPUBufferUsage_MapRead));
}

CAMLprim value opentui_wgpu_buffer_usage_copy_destination(value unit) {
  CAMLparam1(unit);
  (void)unit;
  CAMLreturn(caml_copy_int64((int64_t)WGPUBufferUsage_CopyDst));
}

/* ---- pipelines and draws ---------------------------------------------- */

CAMLprim value opentui_wgpu_device_create_shader_module(
    value device_value,
    value wgsl) {
  CAMLparam2(device_value, wgsl);
  WGPUDevice device = (WGPUDevice)(uintptr_t)Int64_val(device_value);

  WGPUShaderSourceWGSL source;
  memset(&source, 0, sizeof source);
  source.chain.next = NULL;
  source.chain.sType = WGPUSType_ShaderSourceWGSL;
  source.code.data = String_val(wgsl);
  source.code.length = caml_string_length(wgsl);

  WGPUShaderModuleDescriptor descriptor;
  memset(&descriptor, 0, sizeof descriptor);
  descriptor.label = opentui_wgpu_label("opentui-wgpu-shader");
  descriptor.nextInChain = &source.chain;

  WGPUShaderModule module = wgpuDeviceCreateShaderModule(device, &descriptor);
  { char d[96]; snprintf(d,96,"CREATE shader -> %llu", (unsigned long long)(uintptr_t)module); opentui_wgpu_diag_push(d); }
  CAMLreturn(opentui_wgpu_make_handle_pair(
      module != NULL,
      (uint64_t)(uintptr_t)module));
}

CAMLprim value opentui_wgpu_shader_module_release(value module) {
  CAMLparam1(module);
  wgpuShaderModuleRelease((WGPUShaderModule)(uintptr_t)Int64_val(module));
  CAMLreturn(Val_unit);
}

/* One uniform binding visible to vertex and fragment stages. */
CAMLprim value opentui_wgpu_device_create_uniform_bind_group_layout(
    value device_value) {
  CAMLparam1(device_value);
  WGPUDevice device = (WGPUDevice)(uintptr_t)Int64_val(device_value);

  WGPUBindGroupLayoutEntry entry;
  memset(&entry, 0, sizeof entry);
  entry.binding = 0;
  entry.visibility = WGPUShaderStage_Vertex | WGPUShaderStage_Fragment;
  entry.buffer.type = WGPUBufferBindingType_Uniform;
  entry.buffer.hasDynamicOffset = WGPU_FALSE;
  entry.buffer.minBindingSize = 0;

  WGPUBindGroupLayoutDescriptor descriptor;
  memset(&descriptor, 0, sizeof descriptor);
  descriptor.label = opentui_wgpu_label("opentui-wgpu-uniform-layout");
  descriptor.entryCount = 1;
  descriptor.entries = &entry;

  WGPUBindGroupLayout layout =
      wgpuDeviceCreateBindGroupLayout(device, &descriptor);
  { char d[96]; snprintf(d,96,"CREATE bgl -> %llu", (unsigned long long)(uintptr_t)layout); opentui_wgpu_diag_push(d); }
  CAMLreturn(opentui_wgpu_make_handle_pair(
      layout != NULL,
      (uint64_t)(uintptr_t)layout));
}

CAMLprim value opentui_wgpu_bind_group_layout_release(value layout) {
  CAMLparam1(layout);
  wgpuBindGroupLayoutRelease((WGPUBindGroupLayout)(uintptr_t)Int64_val(layout));
  CAMLreturn(Val_unit);
}

CAMLprim value opentui_wgpu_device_create_pipeline_layout(
    value device_value,
    value layout_value) {
  CAMLparam2(device_value, layout_value);
  WGPUDevice device = (WGPUDevice)(uintptr_t)Int64_val(device_value);
  WGPUBindGroupLayout bind_group_layout =
      (WGPUBindGroupLayout)(uintptr_t)Int64_val(layout_value);

  WGPUPipelineLayoutDescriptor descriptor;
  memset(&descriptor, 0, sizeof descriptor);
  descriptor.label = opentui_wgpu_label("opentui-wgpu-pipeline-layout");
  descriptor.bindGroupLayoutCount = 1;
  descriptor.bindGroupLayouts = &bind_group_layout;

  WGPUPipelineLayout pipeline_layout =
      wgpuDeviceCreatePipelineLayout(device, &descriptor);
  { char d[96]; snprintf(d,96,"CREATE pl -> %llu", (unsigned long long)(uintptr_t)pipeline_layout); opentui_wgpu_diag_push(d); }
  CAMLreturn(opentui_wgpu_make_handle_pair(
      pipeline_layout != NULL,
      (uint64_t)(uintptr_t)pipeline_layout));
}

CAMLprim value opentui_wgpu_pipeline_layout_release(value layout) {
  CAMLparam1(layout);
  wgpuPipelineLayoutRelease((WGPUPipelineLayout)(uintptr_t)Int64_val(layout));
  CAMLreturn(Val_unit);
}

/* Position + normal interleaved vertices, triangle list, back-face culling,
   one rgba8unorm target without blending or depth. */
CAMLprim value opentui_wgpu_device_create_render_pipeline(
    value device_value,
    value options) {
  CAMLparam2(device_value, options);
  WGPUDevice device = (WGPUDevice)(uintptr_t)Int64_val(device_value);
  WGPUPipelineLayout layout =
      (WGPUPipelineLayout)(uintptr_t)Int64_val(Field(options, 0));
  WGPUShaderModule shader_module =
      (WGPUShaderModule)(uintptr_t)Int64_val(Field(options, 1));
  const char *vs_name = String_val(Field(options, 2));
  const char *fs_name = String_val(Field(options, 3));
  WGPUTextureFormat target_format =
      (WGPUTextureFormat)Long_val(Field(options, 4));

  WGPUVertexAttribute attributes[2];
  memset(attributes, 0, sizeof attributes);
  attributes[0].format = WGPUVertexFormat_Float32x3;
  attributes[0].offset = 0;
  attributes[0].shaderLocation = 0;
  attributes[1].format = WGPUVertexFormat_Float32x3;
  attributes[1].offset = 12;
  attributes[1].shaderLocation = 1;

  WGPUVertexBufferLayout buffer_layout;
  memset(&buffer_layout, 0, sizeof buffer_layout);
  buffer_layout.stepMode = WGPUVertexStepMode_Vertex;
  buffer_layout.arrayStride = 24;
  buffer_layout.attributeCount = 2;
  buffer_layout.attributes = attributes;

  WGPUVertexState vertex;
  memset(&vertex, 0, sizeof vertex);
  vertex.module = shader_module;
  vertex.entryPoint.data = vs_name;
  vertex.entryPoint.length = strlen(vs_name);
  vertex.bufferCount = 1;
  vertex.buffers = &buffer_layout;

  WGPUPrimitiveState primitive;
  memset(&primitive, 0, sizeof primitive);
  primitive.topology = WGPUPrimitiveTopology_TriangleList;
  primitive.frontFace = WGPUFrontFace_CCW;
  primitive.cullMode = WGPUCullMode_Back;

  WGPUColorTargetState color_target;
  memset(&color_target, 0, sizeof color_target);
  color_target.format = target_format;
  color_target.blend = NULL;
  color_target.writeMask = WGPUColorWriteMask_All;

  WGPUFragmentState fragment;
  memset(&fragment, 0, sizeof fragment);
  fragment.module = shader_module;
  fragment.entryPoint.data = fs_name;
  fragment.entryPoint.length = strlen(fs_name);
  fragment.targetCount = 1;
  fragment.targets = &color_target;

  WGPURenderPipelineDescriptor descriptor;
  memset(&descriptor, 0, sizeof descriptor);
  descriptor.label = opentui_wgpu_label("opentui-wgpu-render-pipeline");
  descriptor.layout = layout;
  descriptor.vertex = vertex;
  descriptor.primitive = primitive;
  descriptor.multisample.count = 1;
  descriptor.multisample.mask = 0xFFFFFFFFu;
  descriptor.fragment = &fragment;

  WGPURenderPipeline pipeline =
      wgpuDeviceCreateRenderPipeline(device, &descriptor);
  { char d[96]; snprintf(d,96,"CREATE rp -> %llu", (unsigned long long)(uintptr_t)pipeline); opentui_wgpu_diag_push(d); }
  CAMLreturn(opentui_wgpu_make_handle_pair(
      pipeline != NULL,
      (uint64_t)(uintptr_t)pipeline));
}

CAMLprim value opentui_wgpu_render_pipeline_release(value pipeline) {
  CAMLparam1(pipeline);
  wgpuRenderPipelineRelease((WGPURenderPipeline)(uintptr_t)Int64_val(pipeline));
  CAMLreturn(Val_unit);
}

CAMLprim value opentui_wgpu_device_create_uniform_bind_group(
    value device_value,
    value layout_value,
    value buffer_value,
    value size) {
  CAMLparam4(device_value, layout_value, buffer_value, size);
  WGPUDevice device = (WGPUDevice)(uintptr_t)Int64_val(device_value);
  WGPUBindGroupLayout layout =
      (WGPUBindGroupLayout)(uintptr_t)Int64_val(layout_value);
  WGPUBuffer buffer = (WGPUBuffer)(uintptr_t)Int64_val(buffer_value);

  WGPUBindGroupEntry entry;
  memset(&entry, 0, sizeof entry);
  entry.binding = 0;
  entry.buffer = buffer;
  entry.offset = 0;
  entry.size = (uint64_t)Int64_val(size);

  WGPUBindGroupDescriptor descriptor;
  memset(&descriptor, 0, sizeof descriptor);
  descriptor.label = opentui_wgpu_label("opentui-wgpu-uniform-group");
  descriptor.layout = layout;
  descriptor.entryCount = 1;
  descriptor.entries = &entry;

  WGPUBindGroup group = wgpuDeviceCreateBindGroup(device, &descriptor);
  { char d[96]; snprintf(d,96,"CREATE bg -> %llu", (unsigned long long)(uintptr_t)group); opentui_wgpu_diag_push(d); }
  CAMLreturn(opentui_wgpu_make_handle_pair(
      group != NULL,
      (uint64_t)(uintptr_t)group));
}

CAMLprim value opentui_wgpu_bind_group_release(value group) {
  CAMLparam1(group);
  wgpuBindGroupRelease((WGPUBindGroup)(uintptr_t)Int64_val(group));
  CAMLreturn(Val_unit);
}

CAMLprim value opentui_wgpu_queue_write_buffer_bytes(
    value queue_value,
    value buffer_value,
    value offset,
    value data) {
  CAMLparam4(queue_value, buffer_value, offset, data);
  WGPUQueue queue = (WGPUQueue)(uintptr_t)Int64_val(queue_value);
  WGPUBuffer buffer = (WGPUBuffer)(uintptr_t)Int64_val(buffer_value);
  mlsize_t size = caml_string_length(data);
  wgpuQueueWriteBuffer(queue, buffer, (uint64_t)Int64_val(offset),
                       String_val(data), size);
  CAMLreturn(Val_unit);
}

CAMLprim value opentui_wgpu_encoder_render_draw_indexed(
    value encoder_value,
    value draw) {
  CAMLparam2(encoder_value, draw);
  WGPUCommandEncoder encoder =
      (WGPUCommandEncoder)(uintptr_t)Int64_val(encoder_value);
  WGPUTextureView view =
      (WGPUTextureView)(uintptr_t)Int64_val(Field(draw, 0));
  value clear_color = Field(draw, 1);
  WGPURenderPipeline pipeline =
      (WGPURenderPipeline)(uintptr_t)Int64_val(Field(draw, 2));
  WGPUBindGroup group = (WGPUBindGroup)(uintptr_t)Int64_val(Field(draw, 3));
  WGPUBuffer vertices = (WGPUBuffer)(uintptr_t)Int64_val(Field(draw, 4));
  uint64_t vertex_size = (uint64_t)Int64_val(Field(draw, 5));
  WGPUBuffer indices = (WGPUBuffer)(uintptr_t)Int64_val(Field(draw, 6));
  uint64_t index_size = (uint64_t)Int64_val(Field(draw, 7));
  uint32_t index_count = (uint32_t)Long_val(Field(draw, 8));
  WGPURenderPassColorAttachment attachment;
  memset(&attachment, 0, sizeof attachment);
  attachment.view = view;
  attachment.depthSlice = WGPU_DEPTH_SLICE_UNDEFINED;
  attachment.loadOp = WGPULoadOp_Clear;
  attachment.storeOp = WGPUStoreOp_Store;
  attachment.clearValue.r = Double_val(Field(clear_color, 0));
  attachment.clearValue.g = Double_val(Field(clear_color, 1));
  attachment.clearValue.b = Double_val(Field(clear_color, 2));
  attachment.clearValue.a = Double_val(Field(clear_color, 3));

  WGPURenderPassDescriptor descriptor;
  memset(&descriptor, 0, sizeof descriptor);
  descriptor.label = opentui_wgpu_label("opentui-wgpu-draw-pass");
  descriptor.colorAttachmentCount = 1;
  descriptor.colorAttachments = &attachment;

  {
    char probe[128];
    snprintf(probe, sizeof probe,
             "DRAW vb=%llu ib=%llu vsz=%llu isz=%llu n=%u",
             (unsigned long long)(uintptr_t)vertices,
             (unsigned long long)(uintptr_t)indices,
             (unsigned long long)vertex_size,
             (unsigned long long)index_size, index_count);
    opentui_wgpu_diag_push(probe);
  }

  WGPURenderPassEncoder pass =
      wgpuCommandEncoderBeginRenderPass(encoder, &descriptor);
  wgpuRenderPassEncoderSetPipeline(pass, pipeline);
  wgpuRenderPassEncoderSetBindGroup(pass, 0, group, 0, NULL);
  wgpuRenderPassEncoderSetVertexBuffer(pass, 0, vertices, 0, vertex_size);
  wgpuRenderPassEncoderSetIndexBuffer(pass, indices, WGPUIndexFormat_Uint16, 0,
                                      index_size);
  wgpuRenderPassEncoderDrawIndexed(pass, index_count, 1, 0, 0, 0);
  wgpuRenderPassEncoderEnd(pass);
  wgpuRenderPassEncoderRelease(pass);
  CAMLreturn(Val_unit);
}

/* Temporary Phase-1 probe: full triangle sequence on one device, entirely
   inside C. Returns 1 and writes the center pixel to *out_pixel when the
   round trip works. */
CAMLprim value opentui_wgpu_debug_triangle(value device_value,
                                           value out_pixel) {
  CAMLparam2(device_value, out_pixel);
  WGPUDevice dev = (WGPUDevice)(uintptr_t)Int64_val(device_value);

  static const char *WGSL =
      "struct Uniforms { mvp: mat4x4<f32>, model: mat4x4<f32>, color: vec4<f32> };\n"
      "@group(0) @binding(0) var<uniform> u : Uniforms;\n"
      "struct VSOut { @builtin(position) pos: vec4<f32>, @location(0) n: vec3<f32> };\n"
      "@vertex fn vs_main(@location(0) pos: vec3<f32>, @location(1) n: vec3<f32>) -> VSOut {\n"
      "  var o: VSOut; o.pos = u.mvp * vec4<f32>(pos,1.0); o.n = n; return o; }\n"
      "@fragment fn fs_main(i: VSOut) -> @location(0) vec4<f32> { return u.color; }\n";

  WGPUShaderSourceWGSL src;
  memset(&src, 0, sizeof src);
  src.chain.sType = WGPUSType_ShaderSourceWGSL;
  src.code.data = WGSL;
  src.code.length = strlen(WGSL);
  WGPUShaderModuleDescriptor smd;
  memset(&smd, 0, sizeof smd);
  smd.label = opentui_wgpu_label("dbg-shader");
  smd.nextInChain = &src.chain;
  WGPUShaderModule sh = wgpuDeviceCreateShaderModule(dev, &smd);

  WGPUBindGroupLayoutEntry ble;
  memset(&ble, 0, sizeof ble);
  ble.binding = 0;
  ble.visibility = WGPUShaderStage_Vertex | WGPUShaderStage_Fragment;
  ble.buffer.type = WGPUBufferBindingType_Uniform;
  WGPUBindGroupLayoutDescriptor bld;
  memset(&bld, 0, sizeof bld);
  bld.label = opentui_wgpu_label("dbg-bgl");
  bld.entryCount = 1;
  bld.entries = &ble;
  WGPUBindGroupLayout bgl = wgpuDeviceCreateBindGroupLayout(dev, &bld);

  WGPUPipelineLayoutDescriptor pld;
  memset(&pld, 0, sizeof pld);
  pld.label = opentui_wgpu_label("dbg-pl");
  pld.bindGroupLayoutCount = 1;
  pld.bindGroupLayouts = &bgl;
  WGPUPipelineLayout pl = wgpuDeviceCreatePipelineLayout(dev, &pld);

  WGPUVertexAttribute attrs[2];
  memset(attrs, 0, sizeof attrs);
  attrs[0].format = WGPUVertexFormat_Float32x3;
  attrs[0].shaderLocation = 0;
  attrs[1].format = WGPUVertexFormat_Float32x3;
  attrs[1].offset = 12;
  attrs[1].shaderLocation = 1;
  WGPUVertexBufferLayout vbl;
  memset(&vbl, 0, sizeof vbl);
  vbl.stepMode = WGPUVertexStepMode_Vertex;
  vbl.arrayStride = 24;
  vbl.attributeCount = 2;
  vbl.attributes = attrs;
  WGPUVertexState vs;
  memset(&vs, 0, sizeof vs);
  vs.module = sh;
  vs.entryPoint.data = "vs_main";
  vs.entryPoint.length = 7;
  vs.bufferCount = 1;
  vs.buffers = &vbl;
  WGPUPrimitiveState prim;
  memset(&prim, 0, sizeof prim);
  prim.topology = WGPUPrimitiveTopology_TriangleList;
  prim.frontFace = WGPUFrontFace_CCW;
  prim.cullMode = WGPUCullMode_None; /* DBG */
  WGPUColorTargetState cts;
  memset(&cts, 0, sizeof cts);
  cts.format = WGPUTextureFormat_RGBA8Unorm;
  cts.writeMask = WGPUColorWriteMask_All;
  WGPUFragmentState fs;
  memset(&fs, 0, sizeof fs);
  fs.module = sh;
  fs.entryPoint.data = "fs_main";
  fs.entryPoint.length = 7;
  fs.targetCount = 1;
  fs.targets = &cts;
  WGPUMultisampleState ms;
  memset(&ms, 0, sizeof ms);
  ms.count = 1;
  ms.mask = 0xFFFFFFFFu;
  WGPURenderPipelineDescriptor rpd;
  memset(&rpd, 0, sizeof rpd);
  rpd.label = opentui_wgpu_label("dbg-rp");
  rpd.layout = pl;
  rpd.vertex = vs;
  rpd.primitive = prim;
  rpd.multisample = ms;
  rpd.fragment = &fs;
  WGPURenderPipeline rp = wgpuDeviceCreateRenderPipeline(dev, &rpd);

  float verts[18] = {-1,-1,0.2f, 0,0,0, 3,-1,0.2f, 0,0,0,
                     -1,3,0.2f, 0,0,0};
  unsigned short idx[3] = {0,1,2};

  WGPUBufferDescriptor bd;
  memset(&bd, 0, sizeof bd);
  bd.label = opentui_wgpu_label("dbg-vb");
  bd.usage = WGPUBufferUsage_Vertex | WGPUBufferUsage_CopyDst;
  bd.size = sizeof verts;
  WGPUBuffer vb = wgpuDeviceCreateBuffer(dev, &bd);
  bd.label = opentui_wgpu_label("dbg-ib");
  bd.usage = WGPUBufferUsage_Index | WGPUBufferUsage_CopyDst;
  bd.size = Wgpu_align4_size(sizeof idx);
  WGPUBuffer ib = wgpuDeviceCreateBuffer(dev, &bd);
  bd.label = opentui_wgpu_label("dbg-ub");
  bd.usage = WGPUBufferUsage_Uniform | WGPUBufferUsage_CopyDst;
  bd.size = 160;
  WGPUBuffer ub = wgpuDeviceCreateBuffer(dev, &bd);

  unsigned char uniforms[160];
  memset(uniforms, 0, sizeof uniforms);
  float identity[16] = {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1};
  memcpy(uniforms, identity, 64);
  memcpy(uniforms + 64, identity, 64);
  float red[4] = {1.0f, 0.0f, 0.0f, 1.0f};
  memcpy(uniforms + 128, red, 16);

  WGPUQueue queue = wgpuDeviceGetQueue(dev);
  wgpuQueueWriteBuffer(queue, vb, 0, verts, sizeof verts);
  unsigned char ib_padded[8];
  memset(ib_padded, 0, sizeof ib_padded);
  memcpy(ib_padded, idx, sizeof idx);
  wgpuQueueWriteBuffer(queue, ib, 0, ib_padded, sizeof ib_padded);
  wgpuQueueWriteBuffer(queue, ub, 0, uniforms, sizeof uniforms);

  WGPUTextureDescriptor td;
  memset(&td, 0, sizeof td);
  td.usage = WGPUTextureUsage_RenderAttachment | WGPUTextureUsage_CopySrc;
  td.dimension = WGPUTextureDimension_2D;
  td.size.width = 8;
  td.size.height = 8;
  td.size.depthOrArrayLayers = 1;
  td.format = WGPUTextureFormat_RGBA8Unorm;
  td.mipLevelCount = 1;
  td.sampleCount = 1;
  td.label = opentui_wgpu_label("dbg-target");
  WGPUTexture tex = wgpuDeviceCreateTexture(dev, &td);
  WGPUTextureView view = wgpuTextureCreateView(tex, NULL);

  WGPUBindGroupEntry bge;
  memset(&bge, 0, sizeof bge);
  bge.binding = 0;
  bge.buffer = ub;
  bge.offset = 0;
  bge.size = 160;
  WGPUBindGroupDescriptor bgd;
  memset(&bgd, 0, sizeof bgd);
  bgd.label = opentui_wgpu_label("dbg-bg");
  bgd.layout = bgl;
  bgd.entryCount = 1;
  bgd.entries = &bge;
  WGPUBindGroup bg = wgpuDeviceCreateBindGroup(dev, &bgd);

  WGPUCommandEncoderDescriptor ed;
  memset(&ed, 0, sizeof ed);
  ed.label = opentui_wgpu_label("dbg-enc");
  WGPUCommandEncoder enc = wgpuDeviceCreateCommandEncoder(dev, &ed);

  static const double CLEAR[4] = {0, 0, 0, 1};
  WGPURenderPassColorAttachment att;
  memset(&att, 0, sizeof att);
  att.view = view;
  att.depthSlice = WGPU_DEPTH_SLICE_UNDEFINED;
  att.loadOp = WGPULoadOp_Clear;
  att.storeOp = WGPUStoreOp_Store;
  memcpy(&att.clearValue, CLEAR, sizeof CLEAR);
  WGPURenderPassDescriptor pd;
  memset(&pd, 0, sizeof pd);
  pd.label = opentui_wgpu_label("dbg-pass");
  pd.colorAttachmentCount = 1;
  pd.colorAttachments = &att;
  WGPURenderPassEncoder pass = wgpuCommandEncoderBeginRenderPass(enc, &pd);
  wgpuRenderPassEncoderSetPipeline(pass, rp);
  wgpuRenderPassEncoderSetBindGroup(pass, 0, bg, 0, NULL);
  wgpuRenderPassEncoderSetVertexBuffer(pass, 0, vb, 0, sizeof verts);
  wgpuRenderPassEncoderSetIndexBuffer(pass, ib, WGPUIndexFormat_Uint16, 0,
                                      sizeof idx);
  wgpuRenderPassEncoderDrawIndexed(pass, 3, 1, 0, 0, 0);
  wgpuRenderPassEncoderEnd(pass);
  wgpuRenderPassEncoderRelease(pass);

  WGPUCommandBuffer cb = wgpuCommandEncoderFinish(enc, NULL);
  wgpuQueueSubmit(queue, 1, &cb);

  /* staging readback */
  WGPUBufferDescriptor rd;
  memset(&rd, 0, sizeof rd);
  rd.label = opentui_wgpu_label("dbg-readback");
  rd.usage = WGPUBufferUsage_MapRead | WGPUBufferUsage_CopyDst;
  rd.size = 256 * 8;
  WGPUBuffer stage = wgpuDeviceCreateBuffer(dev, &rd);

  WGPUCommandEncoderDescriptor ed2;
  memset(&ed2, 0, sizeof ed2);
  ed2.label = opentui_wgpu_label("dbg-copy-enc");
  WGPUCommandEncoder enc2 = wgpuDeviceCreateCommandEncoder(dev, &ed2);
  WGPUTexelCopyTextureInfo csrc;
  memset(&csrc, 0, sizeof csrc);
  csrc.texture = tex;
  csrc.aspect = WGPUTextureAspect_All;
  WGPUTexelCopyBufferLayout clayout;
  memset(&clayout, 0, sizeof clayout);
  clayout.bytesPerRow = 256;
  clayout.rowsPerImage = 8;
  WGPUTexelCopyBufferInfo cdst;
  memset(&cdst, 0, sizeof cdst);
  cdst.layout = clayout;
  cdst.buffer = stage;
  WGPUExtent3D csize = {8, 8, 1};
  wgpuCommandEncoderCopyTextureToBuffer(enc2, &csrc, &cdst, &csize);
  WGPUCommandBuffer cb2 = wgpuCommandEncoderFinish(enc2, NULL);
  wgpuQueueSubmit(queue, 1, &cb2);

  opentui_wgpu_wait mw;
  memset(&mw, 0, sizeof mw);
  WGPUBufferMapCallbackInfo mi;
  memset(&mi, 0, sizeof mi);
  mi.mode = WGPUCallbackMode_WaitAnyOnly;
  mi.callback = opentui_wgpu_buffer_map_callback;
  mi.userdata1 = &mw;
  wgpuBufferMapAsync(stage, WGPUMapMode_Read, 0, 256 * 8, mi);
  while (mw.done == 0) {
    wgpuDevicePoll(dev, WGPU_FALSE, NULL);
    if (mw.done == 0) usleep(1000);
  }

  int result = -1;
  if (mw.status == WGPUMapAsyncStatus_Success) {
    const unsigned char *px =
        (const unsigned char *)wgpuBufferGetMappedRange(stage, 0, 256 * 8);
    unsigned char center_r = px[((4 * 256) + (4 * 4)) + 0];
    unsigned char center_a = px[((4 * 256) + (4 * 4)) + 3];
    char line[128];
    snprintf(line, sizeof line,
             "DBG-C center r=%u g=%u b=%u a=%u (map status %d)", center_r,
             px[((4 * 256) + (4 * 4)) + 1], px[((4 * 256) + (4 * 4)) + 2],
             center_a, (int)WGPUMapAsyncStatus_Success);
    opentui_wgpu_diag_push(line);
    result = (int)center_r;
    wgpuBufferUnmap(stage);
  } else {
    char line[128];
    snprintf(line, sizeof line, "DBG-C map status=%d", (int)mw.status);
    opentui_wgpu_diag_push(line);
    result = -2;
  }
  CAMLreturn(Val_int(result));
}
