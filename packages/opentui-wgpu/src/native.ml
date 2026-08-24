module Instance = Native_token.Instance
module Adapter = Native_token.Adapter
module Device = Native_token.Device
module Queue = Native_token.Queue
module Texture = Native_token.Texture
module Texture_view = Native_token.Texture_view
module Buffer = Native_token.Buffer
module Command_encoder = Native_token.Command_encoder
module Command_buffer = Native_token.Command_buffer
module Shader_module = Native_token.Shader_module
module Bind_group_layout = Native_token.Bind_group_layout
module Pipeline_layout = Native_token.Pipeline_layout
module Render_pipeline = Native_token.Render_pipeline
module Bind_group = Native_token.Bind_group
module Compute_pipeline = Native_token.Compute_pipeline
module Sampler = Native_token.Sampler

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

external texture_usage_copy_destination_c : unit -> int64
  = "opentui_wgpu_texture_usage_copy_destination"

external buffer_usage_map_read_c : unit -> int64
  = "opentui_wgpu_buffer_usage_map_read"

external buffer_usage_copy_destination_c : unit -> int64
  = "opentui_wgpu_buffer_usage_copy_destination"

external enable_diagnostics : unit -> unit
  = "opentui_wgpu_enable_diagnostics"

external drain_diagnostics : max:int -> string list
  = "opentui_wgpu_drain_diagnostics"

external device_create_shader_module :
  Device.t -> wgsl:string -> creation
  = "opentui_wgpu_device_create_shader_module"

external shader_module_release : Shader_module.t -> unit
  = "opentui_wgpu_shader_module_release"

external device_create_uniform_bind_group_layout :
  Device.t -> creation = "opentui_wgpu_device_create_uniform_bind_group_layout"

external bind_group_layout_release : Bind_group_layout.t -> unit
  = "opentui_wgpu_bind_group_layout_release"

external device_create_pipeline_layout :
  Device.t -> Bind_group_layout.t -> creation
  = "opentui_wgpu_device_create_pipeline_layout"

external pipeline_layout_release : Pipeline_layout.t -> unit
  = "opentui_wgpu_pipeline_layout_release"

(* layout, module, vs entry, fs entry, target format *)
type pipeline_options =
  Pipeline_layout.t * Shader_module.t * string * string * int

external device_create_render_pipeline :
  Device.t -> pipeline_options -> creation
  = "opentui_wgpu_device_create_render_pipeline"

external render_pipeline_release : Render_pipeline.t -> unit
  = "opentui_wgpu_render_pipeline_release"

external device_create_uniform_bind_group :
  Device.t -> Bind_group_layout.t -> Buffer.t -> size:int64 -> creation
  = "opentui_wgpu_device_create_uniform_bind_group"

external bind_group_release : Bind_group.t -> unit
  = "opentui_wgpu_bind_group_release"

external queue_write_buffer_bytes :
  Queue.t -> Buffer.t -> offset:int64 -> string -> unit
  = "opentui_wgpu_queue_write_buffer_bytes"

(* texture, data, bytes per row, width, height *)
type write_texture_options =
  Texture.t * string * int64 * int * int

external queue_write_texture_bytes :
  Queue.t -> write_texture_options -> unit
  = "opentui_wgpu_queue_write_texture_bytes"

(* pipeline, bind group,
   vertex buffer + byte size, index buffer + byte size, index count *)
type draw_call =
  Render_pipeline.t
  * Bind_group.t
  * Buffer.t * int64
  * Buffer.t * int64
  * int

external encoder_render_draws_indexed :
  Command_encoder.t ->
  Texture_view.t -> clear_color -> draw_call list -> unit
  = "opentui_wgpu_encoder_render_draws_indexed"

external buffer_usage_storage_c : unit -> int64
  = "opentui_wgpu_buffer_usage_storage"

external texture_usage_texture_binding_c : unit -> int64
  = "opentui_wgpu_texture_usage_texture_binding"

(* layout, shader module, entry point *)
type compute_pipeline_options =
  Pipeline_layout.t * Shader_module.t * string

external device_create_compute_pipeline :
  Device.t -> compute_pipeline_options -> creation
  = "opentui_wgpu_device_create_compute_pipeline"

external compute_pipeline_release : Compute_pipeline.t -> unit
  = "opentui_wgpu_compute_pipeline_release"

external device_create_supersampling_bind_group_layout :
  Device.t -> creation
  = "opentui_wgpu_device_create_supersampling_bind_group_layout"

(* layout, texture view, storage buffer + size, params buffer *)
type compute_bind_group_options =
  Bind_group_layout.t * Texture_view.t * Buffer.t * int64 * Buffer.t

external device_create_compute_bind_group :
  Device.t -> compute_bind_group_options -> creation
  = "opentui_wgpu_device_create_compute_bind_group"

(* pipeline, bind group, groups x/y, source storage, destination, size *)
type compute_dispatch_options =
  Compute_pipeline.t * Bind_group.t * int * int * Buffer.t * Buffer.t * int64

external encoder_dispatch_compute_to_buffer :
  Command_encoder.t -> compute_dispatch_options -> unit
  = "opentui_wgpu_encoder_dispatch_compute_to_buffer"

(* address u, address v, mag filter, min filter *)
type sampler_options = int * int * int * int

external device_create_sampler : Device.t -> sampler_options -> creation
  = "opentui_wgpu_device_create_sampler"

external sampler_release : Sampler.t -> unit
  = "opentui_wgpu_sampler_release"

external device_create_material_bind_group_layout : Device.t -> creation
  = "opentui_wgpu_device_create_material_bind_group_layout"

(* layout, uniform buffer + size, texture view, sampler *)
type material_bind_group_options =
  Bind_group_layout.t * Buffer.t * int64 * Texture_view.t * Sampler.t

external device_create_material_bind_group :
  Device.t -> material_bind_group_options -> creation
  = "opentui_wgpu_device_create_material_bind_group"

(* layout, shader, vs entry, fs entry, target format *)
type textured_pipeline_options =
  Pipeline_layout.t * Shader_module.t * string * string * int

external device_create_textured_render_pipeline :
  Device.t -> textured_pipeline_options -> creation
  = "opentui_wgpu_device_create_textured_render_pipeline"

external debug_triangle_raw : Device.t -> int = "opentui_wgpu_debug_triangle"
