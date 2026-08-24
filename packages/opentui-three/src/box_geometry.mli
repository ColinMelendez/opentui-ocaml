(** Axis-aligned box triangle geometry with per-face normals, matching the
    three.js BoxGeometry vertex layout for one segment per side. *)

val create : ?width:float -> ?height:float -> ?depth:float -> unit -> Geometry.t
(** Defaults of one unit per dimension. Each of the six faces carries four
    vertices with its outward normal and two CCW-when-viewed-from-outside
    triangles, so back-face culling alone hides interior surfaces on this
    convex solid. *)
