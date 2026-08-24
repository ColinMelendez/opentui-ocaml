(** A positional light radiating from the node's world position with a
    distance cutoff, port of three.js PointLight for the phase-2 light
    set.

    Falloff uses the reference's legacy punctual window: a squared ramp
    that reaches zero at [distance] (a non-positive distance means no
    cutoff). Up to four visible point lights are evaluated per frame;
    further lights are ignored, mirroring the fixed uniform slots. *)

val create :
  ?color:Color.t -> ?intensity:float -> ?distance:float -> unit -> Object3d.t
(** Defaults match three.js: white light of intensity one, no cutoff. *)

val color : Object3d.t -> Color.t
(** Raises [Invalid_argument] when [node] is not a point light. *)

val intensity : Object3d.t -> float

val set_intensity : Object3d.t -> float -> unit

val distance : Object3d.t -> float

val set_distance : Object3d.t -> float -> unit
