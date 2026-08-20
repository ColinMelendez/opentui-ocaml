(** Typed [webgpu.h] boundary over the pinned official wgpu-native release.

    The binding modules, audited C stubs, and tests land with the
    three-renderer phases
    ({e docs/major-features/in-progress/three-renderer/feature.md}). The
    pinned release is fetched and validated by the repository Nix flake and
    discovered through pkg-config; this library never downloads artifacts or
    searches unpinned system locations. *)

val pinned_release_tag : string
(** The upstream wgpu-native tag whose headers this binding compiles against.
    The configurator program under [config/] fails the build unless pkg-config
    resolves exactly this version. *)

val pinned_release_version : string
(** The same pin without the leading v. *)

module Error : sig
  type t =
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

val buffer_usage_map_read : int64

val buffer_usage_copy_destination : int64

val submit_clear_frame :
  device ->
  target:render_target ->
  readback:readback ->
  color:floatarray ->
  unit ->
    (unit, Error.t) result
(** Encode one frame that clears the target with [color] (four channel values
    in red, green, blue, alpha order), copy the target into [readback], and
    submit. The call returns after enqueueing; completion is observed by
    {!map_read}, which guarantees all prior submissions are visible. *)

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
