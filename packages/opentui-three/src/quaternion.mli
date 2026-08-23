type t = { mutable x : float; mutable y : float; mutable z : float; mutable w : float }

val identity : unit -> t
val set : t -> float -> float -> float -> float -> unit
val copy : t -> t -> unit

val from_axis_angle : axis:Vector3.t -> angle:float -> t
(** [axis] must be normalized. *)

val normalize : t -> t

val multiply : t -> t -> t -> unit
(** [multiply out a b] writes [a * b]; [out] may alias neither input. *)

val set_from_euler : x:float -> y:float -> z:float -> t
(** Three.js default Euler order XYZ. Additional named orders land when a
    consumer needs them. *)

val to_matrix4 : t -> floatarray -> unit
(** Writes the rotation as a column-major matrix4 into [out]. *)

val from_euler_matrix : floatarray -> t
(** Extracts the rotation of a column-major matrix4 (Shepperd's method). *)
