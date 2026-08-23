type t = floatarray

val size : int
val create : unit -> t
val identity : t -> t
val of_array : float array -> t

val make_translation : t -> float -> float -> float -> t

val copy : t -> t -> unit
(** [copy out src] overwrites [out] with [src]. *)

val multiply : t -> t -> t -> unit
(** [multiply out a b] writes the column-major product [a * b]. [out] must not
    alias [a] or [b]. *)

val compose :
  t -> Vector3.t -> Quaternion.t -> Vector3.t -> unit
(** [compose out position rotation scale] fuses translation, quaternion
    rotation, and scale into one write, matching three.js Matrix4.compose. *)

val perspective :
  fov_degrees:float ->
  aspect:float ->
  ?near:float ->
  ?far:float ->
  t ->
    unit
(** Vertical field of view in degrees, right-handed look-down-negative-Z
    volume with WebGPU depth range. *)

val look_at : up:Vector3.t -> eye:Vector3.t -> target:Vector3.t -> t -> unit
(** Writes a view matrix for a camera at [eye] looking toward [target].
    Degenerate directions leave [out] untouched. *)

val invert : t -> t -> bool
(** [invert input output] runs Gauss-Jordan elimination with partial
    pivoting; returns false when singular and leaves [output] untouched. *)

val transform_point : t -> Vector3.t -> Vector3.t
(** Transforms [v] in place including translation and perspective divide. *)
