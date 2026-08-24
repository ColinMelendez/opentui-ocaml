(** Uniform ambient illumination added to every lambert surface regardless
    of orientation, port of three.js AmbientLight. *)

val create : ?color:Color.t -> ?intensity:float -> unit -> Object3d.t
(** Defaults match three.js: white light of intensity one. *)

val color : Object3d.t -> Color.t
(** Raises [Invalid_argument] when [node] is not an ambient light. *)

val intensity : Object3d.t -> float

val set_intensity : Object3d.t -> float -> unit
