module Instance = Native_token.Instance
module Adapter = Native_token.Adapter
module Device = Native_token.Device
module Queue = Native_token.Queue
module Texture = Native_token.Texture
module Texture_view = Native_token.Texture_view
module Buffer = Native_token.Buffer
module Command_encoder = Native_token.Command_encoder
module Command_buffer = Native_token.Command_buffer

(* Raw native status codes; see webgpu.h enum definitions. *)
let request_status_success = 1

let map_status_success = 1

type creation = bool * int64

(* status, handle, message *)
type request = int * int64 * string

(* width, height, format, usage *)
type texture_options = int * int * int * int64

(* size, usage *)
type buffer_options = int64 * int64

(* red, green, blue, alpha *)
type clear_color = float * float * float * float

(* width, height, bytes_per_row *)
type copy_region = int * int * int

external instance_create : unit -> creation = "opentui_wgpu_instance_create"

external instance_release : Instance.t -> unit =
  "opentui_wgpu_instance_release"

external instance_request_adapter :
  Instance.t -> request = "opentui_wgpu_instance_request_adapter"

external adapter_release : Adapter.t -> unit = "opentui_wgpu_adapter_release"

external adapter_request_device :
  Instance.t -> Adapter.t -> request = "opentui_wgpu_adapter_request_device"

external device_release : Device.t -> unit = "opentui_wgpu_device_release"

external device_get_queue : Device.t -> Queue.t =
  "opentui_wgpu_device_get_queue"

external queue_release : Queue.t -> unit = "opentui_wgpu_queue_release"

external device_create_texture :
  Device.t -> texture_options -> creation
  = "opentui_wgpu_device_create_texture"

external texture_release : Texture.t -> unit = "opentui_wgpu_texture_release"

external texture_create_view :
  Texture.t -> creation = "opentui_wgpu_texture_create_view"

external texture_view_release : Texture_view.t -> unit =
  "opentui_wgpu_texture_view_release"

external device_create_buffer :
  Device.t -> buffer_options -> creation
  = "opentui_wgpu_device_create_buffer"

external buffer_release : Buffer.t -> unit = "opentui_wgpu_buffer_release"

external device_create_command_encoder :
  Device.t -> creation = "opentui_wgpu_device_create_command_encoder"

external command_encoder_release : Command_encoder.t -> unit =
  "opentui_wgpu_command_encoder_release"

external encoder_begin_render_pass_clear :
  Command_encoder.t -> Texture_view.t -> clear_color -> unit
  = "opentui_wgpu_encoder_begin_render_pass_clear"

external encoder_copy_texture_to_buffer :
  Command_encoder.t -> Texture.t -> Buffer.t -> copy_region -> unit
  = "opentui_wgpu_encoder_copy_texture_to_buffer"

external command_encoder_finish :
  Command_encoder.t -> creation = "opentui_wgpu_command_encoder_finish"

external command_buffer_release : Command_buffer.t -> unit =
  "opentui_wgpu_command_buffer_release"

external queue_submit_one : Queue.t -> Command_buffer.t -> unit
  = "opentui_wgpu_queue_submit_one"

(* status, message *)
type map_result = int * string

external buffer_map_read_blocking :
  Device.t -> Buffer.t -> size:int64 -> map_result
  = "opentui_wgpu_buffer_map_read_blocking"

external buffer_get_mapped_range_copy :
  Buffer.t ->
  offset:int64 ->
  size:int64 ->
  (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t ->
    int
  = "opentui_wgpu_buffer_get_mapped_range_copy"

external buffer_unmap : Buffer.t -> unit = "opentui_wgpu_buffer_unmap"

external texture_format_rgba8_unorm_c : unit -> int
  = "opentui_wgpu_texture_format_rgba8_unorm"

external texture_usage_render_attachment_c : unit -> int64
  = "opentui_wgpu_texture_usage_render_attachment"

external texture_usage_copy_source_c : unit -> int64
  = "opentui_wgpu_texture_usage_copy_source"

external buffer_usage_map_read_c : unit -> int64
  = "opentui_wgpu_buffer_usage_map_read"

external buffer_usage_copy_destination_c : unit -> int64
  = "opentui_wgpu_buffer_usage_copy_destination"
