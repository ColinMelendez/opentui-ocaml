val buffer_handle_string : Native_token.Buffer.t -> string
(** Typed [webgpu.h] boundary over the pinned official wgpu-native release.

    The binding modules, audited C stubs, and tests land with the
    three-renderer phases
    ({e docs/major-features/in-progress/three-renderer/feature.md}). The
    pinned release is fetched and validated by the repository Nix flake and
    discovered through pkg-config; this library never downloads artifacts or
    searches unpinned system locations. *)

module Native_token = Native_token
(** Tokenized handle types flowing through buffer and draw-frame fields;
    named here so downstream owners can annotate their storage. *)

val pinned_release_tag : string
(** The upstream wgpu-native tag whose headers this binding compiles against.
    The configurator program under [config/] fails the build unless pkg-config
    resolves exactly this version. *)

val pinned_release_version : string
(** The same pin without the leading v. *)

module Error : sig  type t =
    | Closed of { operation : string }
    | Invalid_argument of string
    | Creation_failed of {
        what : string;
        code : int;
        message : string;
      }
    | Map_failed of { code : int; message : string }
    | Native_failure of { operation : string }

  val pp : Format.formatter -> t -> unit

  val message : t -> string
end

type device
(** One WebGPU device together with the instance and adapter that produced it.
    All operations on render targets and readback buffers require their
    creating [device] to stay open; [destroy_device] releases every native
    resource in reverse creation order. *)

val create_device : unit -> (device, Error.t) result
(** Request the default adapter synchronously and open one device on it.
    Failing intermediate requests release every partially created resource. *)

val destroy_device : device -> unit
(** Release the device, its queue, the adapter, and the instance. Repeated
    calls are harmless. Every operation after destruction returns
    [Error.Closed]. *)

val is_closed : device -> bool

type render_target
(** One rgba8unorm 2D texture with a full view, sized in pixels. *)

type readback
(** One map-read staging buffer holding [stride * rows] bytes. *)

val create_render_target :
  device -> width:int -> height:int -> (render_target, Error.t) result

val destroy_render_target : render_target -> unit
(** Release the view and texture. Repeated calls are harmless. Using a
    destroyed target afterwards fails with [Error.Closed]. *)

val create_readback :
  device -> stride:int -> rows:int -> (readback, Error.t) result
(** [stride] must be a multiple of {!readback_stride_alignment}; use
    {!readback_stride}. *)

val create_copy_readback : device -> size:int -> (readback, Error.t) result
(** A map-read staging buffer of exactly [size] bytes for
    buffer-to-buffer copies, which carry no row-alignment requirement -
    unlike the texture-copy readbacks built by {!create_readback}. *)

val destroy_readback : readback -> unit
(** Unmap (when mapped) and release the buffer. Repeated calls are harmless. *)

val readback_stride : width:int -> int
(** [readback_stride ~width] rounds [width * 4] up to the 256-byte alignment
    that [copyTextureToBuffer] requires per row. *)

val readback_stride_alignment : int

val readback_size : readback -> int

val texture_format_rgba8_unorm : int

val texture_usage_render_attachment : int64

val texture_usage_copy_source : int64

val texture_usage_copy_destination : int64

val buffer_usage_map_read : int64

val buffer_usage_copy_destination : int64

type shader_module
type bind_group_layout
type pipeline_layout
type render_pipeline
type bind_group
type compute_pipeline

val buffer_usage_storage : int64

val texture_usage_texture_binding : int64

val create_compute_pipeline :
  device ->
  layout:pipeline_layout ->
  shader:shader_module ->
  entry_point:string ->
    (compute_pipeline, Error.t) result

val destroy_compute_pipeline : compute_pipeline -> unit

val create_supersampling_bind_group_layout :
  device -> (bind_group_layout, Error.t) result
(** The supersampling pass layout: binding 0 the frame texture (loaded via
    [textureLoad], no sampler), binding 1 a read-write storage buffer of
    48-byte cell records, binding 2 a uniform block of three u32s -
    width, height, and algorithm - all visible to the compute stage. *)

val create_compute_bind_group :
  device ->
  layout:bind_group_layout ->
  view:Native_token.Texture_view.t ->
  storage:Native_token.Buffer.t ->
  storage_size:int ->
  params:Native_token.Buffer.t ->
    (bind_group, Error.t) result

val dispatch_compute_pass :
  device ->
  pipeline:compute_pipeline ->
  group:bind_group ->
  groups_x:int ->
  groups_y:int ->
  source:Native_token.Buffer.t ->
  destination:readback ->
    (unit, Error.t) result
(** Encodes one compute pass - pipeline, bind group, one workgroup-grid
    dispatch - copies the whole source storage buffer into [destination],
    and submits. Completion is observed by {!map_read} on [destination]. *)

type draw_frame = {
  pipeline : render_pipeline;
  group : bind_group;
  vertex_buffer : Native_token.Buffer.t;
  vertex_size : int;
  index_buffer : Native_token.Buffer.t;
  index_size : int;
  index_count : int;
}

val submit_draw_frame :
  device ->
  target:render_target ->
  readback:readback ->
  clear:float * float * float * float ->
  draws:draw_frame list ->
  unit ->
    (unit, Error.t) result
(** One frame: clear the target with [clear] (four channel values in red,
    green, blue, alpha order), encode every draw in [draws] in list order as
    one indexed draw each within a single render pass - an empty list encodes
    a clear-only frame - copy the target into [readback], and submit. Uniform
    data must be staged with {!write_buffer_string} beforehand; completion is
    observed by {!map_read}. *)

val map_read : device -> readback -> (unit, Error.t) result
(** Block until the staging buffer maps for reading. Completion is driven by
    the [wgpuDevicePoll] extension inside the stub - buffer-map futures are
    not implemented in the pinned wgpu-native release - and the callback mode
    forbids firing anywhere except our own poll calls, so nothing enters OCaml
    from a foreign thread. Mapping an already-mapped readback fails with
    [Error.Invalid_argument]. *)

val copy_mapped :
  readback ->
  (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t ->
    (unit, Error.t) result
(** Copy the whole mapped range into caller-owned byte-exact staging. The
    destination must hold at least {!readback_size} bytes, which both this
    function and the stub enforce. Decode strictly before {!unmap}; mapped
    memory escapes neither the mapping lifetime nor this module. *)

val unmap : readback -> unit

val enable_diagnostics : unit -> unit
(** Route wgpu-native warnings and errors into an in-memory ring drained by
    [drain_diagnostics]. Callbacks never touch OCaml from foreign threads;
    the ring is drained from the owner domain. *)

val drain_diagnostics : ?max:int -> unit -> string list

val buffer_usage_vertex : int64
val buffer_usage_index : int64
val buffer_usage_uniform : int64

val buffer_usage_copy_source : int64

val create_shader_module :
  device -> wgsl:string -> (shader_module, Error.t) result

val destroy_shader_module : shader_module -> unit

val create_uniform_bind_group_layout :
  device -> (bind_group_layout, Error.t) result
(** One uniform binding at group 0, binding 0, visible to vertex and
    fragment stages. *)

val destroy_bind_group_layout : bind_group_layout -> unit

val create_pipeline_layout :
  device -> bind_group_layout -> (pipeline_layout, Error.t) result

val destroy_pipeline_layout : pipeline_layout -> unit

val create_render_pipeline :
  device ->
  layout:pipeline_layout ->
  shader:shader_module ->
  vs_entry:string ->
  fs_entry:string ->
  target_format:int ->
    (render_pipeline, Error.t) result
(** Interleaved position+normal vertex layout (stride 24, locations 0/1),
    triangle list, CCW front face, back-face culling, no depth, no blend.
    Entry point names must be [vs_main] and [fs_main]. *)

val destroy_render_pipeline : render_pipeline -> unit

val create_uniform_bind_group :
  device -> bind_group_layout -> Native_token.Buffer.t -> size:int ->
    (bind_group, Error.t) result

val destroy_bind_group : bind_group -> unit

type data_texture
(** A CPU-filled rgba8unorm texture with a full view, for material maps. *)

val create_data_texture :
  device -> width:int -> height:int -> (data_texture, Error.t) result

val write_data_texture :
  device -> texture:data_texture -> data:string -> (unit, Error.t) result
(** Replaces the texture contents with [width * height * 4] tightly packed
    RGBA bytes through a queue write. *)

val destroy_data_texture : data_texture -> unit

val data_texture_view : data_texture -> Native_token.Texture_view.t

val address_mode_repeat : int

val address_mode_clamp_to_edge : int

val filter_mode_nearest : int

val filter_mode_linear : int

type sampler

val create_sampler :
  device ->
  address_u:int ->
  address_v:int ->
  mag_filter:int ->
  min_filter:int ->
    (sampler, Error.t) result
(** Wrap and filtering controls for textured materials. Address/filter
    values come from the exposed constants; the native enums are pinned in
    webgpu.h. *)

val destroy_sampler : sampler -> unit

val create_material_bind_group_layout :
  device -> (bind_group_layout, Error.t) result
(** Uniform block at binding 0, float texture at binding 1, filtering
    sampler at binding 2 - the textured-material layout. *)

val create_material_bind_group :
  device ->
  layout:bind_group_layout ->
  uniform_buffer:Native_token.Buffer.t ->
  uniform_size:int ->
  view:Native_token.Texture_view.t ->
  sampler:sampler ->
    (bind_group, Error.t) result

val create_textured_render_pipeline :
  device ->
  layout:pipeline_layout ->
  shader:shader_module ->
  vs_entry:string ->
  fs_entry:string ->
  target_format:int ->
    (render_pipeline, Error.t) result
(** Like {!create_render_pipeline} but over interleaved position + normal +
    uv vertices: stride 32 bytes, uv at location 2 (Float32x2 @24). *)

val write_texture_bytes :
  device ->
  texture:Native_token.Texture.t ->
  data:string ->
  bytes_per_row:int ->
  width:int ->
  height:int ->
    (unit, Error.t) result
(** Uploads tightly packed rgba8unorm rows straight into a texture through
    a queue write. Callers pad [data] themselves when they need copy-style
    row alignment; the write itself carries no stride restriction. *)

val write_buffer_string :
  device -> Native_token.Buffer.t -> offset:int -> string ->
    (unit, Error.t) result
(** Stages caller-packed bytes through a queue write; byte-exact staging
    stays on the caller side. *)

val align4 : int -> int
(** Rounds [n] up to the four-byte alignment that queue writes and uniform
    blocks require. *)

val pack_f32_le : floatarray -> string
val pack_indices_u16 : int array -> string

val create_buffer :
  device -> size:int -> usage:int64 -> (Native_token.Buffer.t, Error.t) result

val destroy_buffer : Native_token.Buffer.t -> unit
(** Releases a raw buffer handle created by [create_buffer]. Idempotence is
    the caller's responsibility at this level; higher-level owners wrap it. *)

val render_target_view : render_target -> Native_token.Texture_view.t

val render_target_texture : render_target -> Native_token.Texture.t
(** The underlying texture for queue writes; borrowing only, destruction
    stays with {!destroy_render_target}. *)

val debug_triangle : device -> int
(** Temporary phase-1 probe: runs an entire red-triangle sequence inside C
    on [device] and reports whether the center pixel read back as red. *)
