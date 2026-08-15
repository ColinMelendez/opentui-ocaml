(** Stateful, frame-by-frame post effects.

    Effects retain only their configuration and animation clock.  They do not
    retain a renderer buffer, so the same effect can safely be applied to
    different renderer-owned surfaces. *)

module Distortion_effect : sig
  type t

  val create :
    ?glitch_chance_per_second:float ->
    ?max_glitch_lines:int ->
    ?min_glitch_duration:float ->
    ?max_glitch_duration:float ->
    ?max_shift_amount:int ->
    ?shift_flip_ratio:float ->
    ?color_glitch_chance:float ->
    unit -> t

  val glitch_chance_per_second : t -> float
  val set_glitch_chance_per_second : t -> float -> unit
  val max_glitch_lines : t -> int
  val set_max_glitch_lines : t -> int -> unit
  val min_glitch_duration : t -> float
  val set_min_glitch_duration : t -> float -> unit
  val max_glitch_duration : t -> float
  val set_max_glitch_duration : t -> float -> unit
  val max_shift_amount : t -> int
  val set_max_shift_amount : t -> int -> unit
  val shift_flip_ratio : t -> float
  val set_shift_flip_ratio : t -> float -> unit
  val color_glitch_chance : t -> float
  val set_color_glitch_chance : t -> float -> unit

  val apply : t -> Buffer.t -> delta_time:float -> (unit, Error.t) result
end

module Vignette_effect : sig
  type t
  val create : ?strength:float -> unit -> t
  val strength : t -> float
  val set_strength : t -> float -> unit
  val apply : t -> Buffer.t -> (unit, Error.t) result
end

module Clouds_effect : sig
  type t
  val create :
    ?scale:float -> ?speed:float -> ?density:float -> ?darkness:float -> unit -> t
  val scale : t -> float
  val set_scale : t -> float -> unit
  val speed : t -> float
  val set_speed : t -> float -> unit
  val density : t -> float
  val set_density : t -> float -> unit
  val darkness : t -> float
  val set_darkness : t -> float -> unit
  val apply : t -> Buffer.t -> delta_time:float -> (unit, Error.t) result
end

module Flames_effect : sig
  type t
  val create : ?scale:float -> ?speed:float -> ?intensity:float -> unit -> t
  val scale : t -> float
  val set_scale : t -> float -> unit
  val speed : t -> float
  val set_speed : t -> float -> unit
  val intensity : t -> float
  val set_intensity : t -> float -> unit
  val apply : t -> Buffer.t -> delta_time:float -> (unit, Error.t) result
end

module Crt_rolling_bar_effect : sig
  type t
  val create :
    ?speed:float -> ?height:float -> ?intensity:float -> ?fade_distance:float -> unit -> t
  val speed : t -> float
  val set_speed : t -> float -> unit
  val height : t -> float
  val set_height : t -> float -> unit
  val intensity : t -> float
  val set_intensity : t -> float -> unit
  val fade_distance : t -> float
  val set_fade_distance : t -> float -> unit
  val apply : t -> Buffer.t -> delta_time:float -> (unit, Error.t) result
end

module Rainbow_text_effect : sig
  type t
  val create :
    ?speed:float -> ?saturation:float -> ?value:float -> ?repeats:float -> unit -> t
  val speed : t -> float
  val set_speed : t -> float -> unit
  val saturation : t -> float
  val set_saturation : t -> float -> unit
  val value : t -> float
  val set_value : t -> float -> unit
  val repeats : t -> float
  val set_repeats : t -> float -> unit
  val apply : t -> Buffer.t -> delta_time:float -> (unit, Error.t) result
end

module DistortionEffect = Distortion_effect
module VignetteEffect = Vignette_effect
module CloudsEffect = Clouds_effect
module FlamesEffect = Flames_effect
module CRTRollingBarEffect = Crt_rolling_bar_effect
module RainbowTextEffect = Rainbow_text_effect
