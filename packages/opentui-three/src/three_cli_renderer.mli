module Wgpu = Opentui_wgpu.Wgpu

module Error : sig
  type t =
    | Gpu of Wgpu.Error.t
    | Buffer of Opentui_core.Error.t
    | Invalid_argument of string
    | Concurrent_draw_scene

  val message : t -> string
end

type super_sample = [ `None | `Cpu | `Gpu ]

val default_super_sample : super_sample
(** The reference constructs with GPU supersampling unless told otherwise;
    until the phase-2 compute pass lands, [`Gpu] aliases the CPU oracle. *)

type t
(** One CLI renderer instance: options, default camera, engine ownership,
    and stats state. *)

val create :
  ?focal_length:float ->
  ?background_color:Opentui_core.Color.t ->
  ?super_sample:super_sample ->
  ?alpha:bool ->
  ?cell_aspect_ratio:float ->
  width:int ->
  height:int ->
  unit ->
    (t, Error.t) result
(** Builds renderer state without touching the GPU. Defaults mirror the
    reference: opaque black background, GPU super sampling, one-degree
    default FOV (focal-length construction derives FOV = 2*atan(height /
    (2*focal)) in degrees), camera at (0,0,3) looking at the origin, near
    0.1, far 1000.

    Aspect ratio resolution order: [cell_aspect_ratio], then the
    CELL_ASPECT_RATIO environment variable, then width / (height * 2) -
    the reference's terminal-cell default. *)

val init : t -> (unit, Error.t) result
(** Opens the WebGPU device and builds the offscreen surface at the current
    render dimensions. Required before any frame is drawn; drawing before
    [init] silently no-ops like the reference. *)

val draw_scene :
  t ->
  root:Object3d.t ->
  buffer:Opentui_core.Owned_buffer.t ->
  delta_time:float ->
    (unit, Error.t) result
(** One frame: submit the scene through the active camera, stage the pixels,
    and write terminal cells into [buffer]. The caller owns clearing
    [buffer]; the reference demos clear it transparent every frame before
    calling. A reentrant call returns {!Error.Concurrent_draw_scene} - a
    deliberate divergence from the reference, which only warns. Drawing
    after {!destroy} or before {!init} returns [Ok ()], matching the
    reference no-op behavior. [delta_time] is accepted for signature parity;
    animations live in scene updates. *)

val set_active_camera : t -> Object3d.t -> unit
(** Raises [Invalid_argument] for non-perspective nodes; orthographic
    cameras land with phase 3. *)

val active_camera : t -> Object3d.t

val set_background_color : Opentui_core.Color.t -> t -> unit

val set_size : ?force:bool -> t -> width:int -> height:int -> (unit, Error.t) result
(** Resizes output dimensions, rebuilds the render surface at the mode's
    render scale, and refreshes the camera aspect plus projection.
    No-ops for unchanged dimensions unless [force]. *)

val toggle_super_sampling : t -> (unit, Error.t) result
(** Cycles [`None] -> [`Cpu] -> [`Gpu] -> [`None] and resizes the render
    surface, matching the reference toggle order. *)

val toggle_debug_stats : t -> unit
(** When enabled, {!draw_scene} draws the stats overlay each frame. *)

val render_stats : t -> buffer:Opentui_core.Owned_buffer.t -> unit
(** Draws the stats overlay once at the reference's fixed offset. The
    MapAsync/SS-Draw splits and algorithm line arrive with the phase-2
    compute pass. *)

val save_to_file : t -> path:string -> (unit, Error.t) result
(** Encodes the most recently staged frame as PNG (8-bit RGBA, render
    dimensions) and writes it to [path]. Drawing before init or after
    destroy no-ops like {!draw_scene}. *)

val get_super_sample : t -> super_sample

type sample_algorithm = [ `Standard | `Pre_squeezed ]

val get_super_sample_algorithm : t -> sample_algorithm

val set_super_sample_algorithm :
  t -> sample_algorithm -> (unit, Error.t) result
(** Selects the reference's supersampling variant used by the [`Gpu] path
    and reported in the stats overlay. *)

val destroy : t -> unit
(** Releases all GPU state; idempotent. *)
