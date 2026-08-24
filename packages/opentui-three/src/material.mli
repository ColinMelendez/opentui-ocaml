type kind =
  | Basic
  | Lambert
  | Phong

type t = {
  kind : kind;
  color : Color.t;
  mutable specular : Color.t;
  mutable shininess : float;
  mutable emissive : Color.t;
  mutable emissive_intensity : float;
}
(** Material state shared across the supported families. [color] is the
    linear-space albedo. The phong-only fields ([specular], [shininess],
    [emissive], [emissive_intensity]) are carried by every material so
    swapping families is a pipeline selection change, matching three.js
    where reassignment swaps programs; basic and lambert ignore them. *)

val color : t -> Color.t

val kind : t -> kind

val specular : t -> Color.t

val shininess : t -> float

val emissive : t -> Color.t

val emissive_intensity : t -> float
