(** A light shining from the node's world position toward its target node's
    world position, port of three.js DirectionalLight.

    The direction is computed at draw time from both nodes' world matrices.
    Like the reference, a target detached from the scene never updates its
    world matrix on its own - leave it at the origin (the default), add it
    to the scene, or update it manually. *)

val create : ?color:Color.t -> ?intensity:float -> unit -> Object3d.t
(** Defaults match three.js: white light of intensity one, positioned above
    the origin, aimed at a fresh target node sitting at the origin. *)

val color : Object3d.t -> Color.t
(** Raises [Invalid_argument] when [node] is not a directional light. *)

val intensity : Object3d.t -> float

val set_intensity : Object3d.t -> float -> unit

val target : Object3d.t -> Object3d.t

val set_target : Object3d.t -> Object3d.t -> unit
