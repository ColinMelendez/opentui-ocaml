type t = { mutable x : float; mutable y : float; mutable z : float }

val create : ?x:float -> ?y:float -> ?z:float -> unit -> t

val copy : t -> t -> unit
(** [copy t v] overwrites [t] with the components of [v]. *)

val clone : t -> t

val set : t -> float -> float -> float -> unit

val add : t -> t -> unit
val sub : t -> t -> unit
val multiply_scalar : t -> float -> unit
val dot : t -> t -> float
val cross_into : t -> t -> t -> unit
val length : t -> float
val normalize : t -> t

val transform_direction : t -> floatarray -> t
(** Applies only the rotation and scale of a column-major matrix4 to [t] and
    normalizes the result, matching three.js transformDirection. *)
