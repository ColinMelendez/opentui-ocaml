(** OCaml-owned Yoga measure callbacks used by renderables with composite
    intrinsic dimensions. *)

type mode = Undefined | Exactly | At_most

type callback =
  width:float -> width_mode:mode -> height:float -> height_mode:mode -> float * float

val attach : Yoga.Node.t -> callback -> (unit, Native.Error.t) result
val detach : Yoga.Node.t -> (unit, Native.Error.t) result
