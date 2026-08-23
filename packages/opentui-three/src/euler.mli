(** Three.js-shaped Euler angles in radians, XYZ order. *)

type t = { mutable x : float; mutable y : float; mutable z : float }

val create : ?x:float -> ?y:float -> ?z:float -> unit -> t
val set : t -> float -> float -> float -> unit

val to_quaternion : order:[ `Xyz ] -> t -> Quaternion.t

val of_quaternion : Quaternion.t -> t
