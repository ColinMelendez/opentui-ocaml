(** Cell emission over an owned buffer: linear GPU pixels become sRGB
    terminal cells through the reference quadrant algorithm or the plain
    full-block path.

    This module is the CPU oracle for the ported supersampling algorithm;
    the phase-2 GPU compute pass must produce identical cells on shared
    fixtures, so its behavior is pinned here by unit tests rather than
    hidden inside the facade. *)

val linear_to_srgb_byte : float -> int
(** One channel of the locked cell-emission transfer function: linear
    [0..1] in, sRGB byte out. Linear 0.5 encodes as 188 - the deliberate
    divergence from the reference's raw-byte truncation. *)

val full_block : int32

val space : int32

type pixel = {
  r : float;
  g : float;
  b : float;
  a : float;
}
(** One staged pixel in linear working space, channels in [0..1]. *)

val sample : string -> width:int -> x:int -> y:int -> pixel
(** Reads one rgba8unorm pixel from a stride-stripped frame. *)

val blend_colors : pixel -> pixel -> pixel
(** Verbatim alpha-over blend from supersampling.wgsl. *)

val average_colors_with_alpha : pixel -> pixel -> pixel -> pixel -> pixel
(** Verbatim four-sample average: pairwise blends in sample order. *)

val luminance : pixel -> float

val distance_squared : pixel -> pixel -> float

val write_none :
  buffer:Opentui_core.Owned_buffer.t ->
  snapshot:string ->
  width:int ->
  height:int ->
    (unit, Opentui_core.Error.t) result
(** None mode: one rendered pixel becomes one full-block cell colored with
    the pixel value converted to sRGB; alpha stays ignored, matching the
    reference path. [snapshot] holds [width * height * 4] bytes. *)

val write_quadrants :
  buffer:Opentui_core.Owned_buffer.t ->
  snapshot:string ->
  output_width:int ->
  output_height:int ->
  ?render_width:int ->
  ?render_height:int ->
    unit -> (unit, Opentui_core.Error.t) result
(** Super-sampled mode: [snapshot] holds the 2x-rendered frame
    ([2*output_width] x [2*output_height] pixels) and each terminal cell is
    classified from its 2x2 pixel block exactly as the reference WGSL
    compute pass does - most-distant pair ordered by luminance, quadrant
    bits TL=8 TR=4 BL=2 BR=1, all-dark/all-light branches averaging with
    alpha blending. *)

val record_size : int
(** Byte size of one GPU CellResult record: bg vec4, fg vec4, char u32,
    three padding u32s. *)

val read_record : string -> int -> int32 * pixel * pixel
(** [read_record records index] decodes character, background, and
    foreground from the [index]'th 48-byte compute output record. Colors
    stay in linear working space; conversion happens at cell write. *)

val write_gpu_records :
  buffer:Opentui_core.Owned_buffer.t ->
  records:string ->
  output_width:int ->
  output_height:int ->
  record_pitch:int ->
    (unit, Opentui_core.Error.t) result
(** [record_pitch] is the compute grid's width in cells - [(render_width +
    1) / 2] - which exceeds [output_width] on oddly-sized surfaces. *)
(** Writes cells decoded from raw compute-pass storage output - the Gpu
    super-sample path's twin of {!write_quadrants}, sharing the same
    sRGB-at-write emission so both paths produce identical buffers. *)
