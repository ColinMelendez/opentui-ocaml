(** A mesh: geometry drawn through one material, the port of three.js Mesh. *)

val create : ?name:string -> Geometry.t -> Material.t -> Object3d.t

val geometry : Object3d.t -> Geometry.t
(** Raises [Invalid_argument] when [node] is not a mesh. *)

val material : Object3d.t -> Material.t
(** Raises [Invalid_argument] when [node] is not a mesh. *)

val set_geometry : Object3d.t -> Geometry.t -> unit
(** Replaces the geometry; renderer-side upload caching keys on the
    geometry instance, so a fresh instance uploads afresh. *)

val set_material : Object3d.t -> Material.t -> unit
(** Swaps the material, including across families (unlit to lambert and
    back), matching per-frame material reassignment in the reference demos. *)
