(** Deterministic post-processing filters over a renderer-owned {!Buffer.t}.

    The reference implementation receives an [OptimizedBuffer] and mutates
    its public typed arrays.  The OCaml port keeps those arrays native-owned:
    filters use the typed color-matrix seam or an explicit buffer snapshot and
    restore.  Every operation therefore reports a structured renderer error. *)

val apply_scanlines :
  Buffer.t -> ?strength:float -> ?step:int -> unit -> (unit, Error.t) result

val apply_invert :
  Buffer.t -> ?strength:float -> unit -> (unit, Error.t) result

val apply_noise :
  Buffer.t -> ?strength:float -> unit -> (unit, Error.t) result

val apply_chromatic_aberration :
  Buffer.t -> ?strength:float -> unit -> (unit, Error.t) result

val default_ascii_ramp : string

val apply_ascii_art :
  Buffer.t ->
  ?ramp:string ->
  ?fg_color:(float * float * float) ->
  ?bg_color:(float * float * float) ->
  unit -> (unit, Error.t) result

val apply_brightness :
  Buffer.t -> ?brightness:float -> ?cell_mask:floatarray -> unit ->
  (unit, Error.t) result

val apply_gain :
  Buffer.t -> ?gain:float -> ?cell_mask:floatarray -> unit ->
  (unit, Error.t) result

val apply_saturation :
  Buffer.t -> ?cell_mask:floatarray -> ?strength:float -> unit ->
  (unit, Error.t) result

module Bloom_effect : sig
  type t

  val create : ?threshold:float -> ?strength:float -> ?radius:int -> unit -> t
  val threshold : t -> float
  val set_threshold : t -> float -> unit
  val strength : t -> float
  val set_strength : t -> float -> unit
  val radius : t -> int
  val set_radius : t -> int -> unit
  val apply : t -> Buffer.t -> (unit, Error.t) result
end

module BloomEffect = Bloom_effect
