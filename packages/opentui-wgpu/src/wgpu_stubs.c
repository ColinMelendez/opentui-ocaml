#include <caml/alloc.h>
#include <caml/bigarray.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

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
