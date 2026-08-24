(** Perspective projection camera, port of three.js PerspectiveCamera with
    the WebGPU depth range (near maps to 0, far to 1).

    Aspect ratio policy: callers pass [aspect] explicitly. The CLI facade
    derives the terminal default - width / (height * 2), honoring
    CELL_ASPECT_RATIO - when it constructs cameras, mirroring
    ThreeCliRenderer; focal-length construction also belongs there because
    it needs the pixel height. *)

val create :
  ?fov_degrees:float ->
  ?aspect:float ->
  ?near:float ->
  ?far:float ->
  ?name:string ->
    unit -> Object3d.t
(** Defaults match three.js: fifty-degree vertical field of view, unit
    aspect, near 0.1, far 1000. The projection matrix is built eagerly. *)

val fov_degrees : Object3d.t -> float

val set_fov_degrees : Object3d.t -> float -> unit

val aspect : Object3d.t -> float

val set_aspect : Object3d.t -> float -> unit

val update_projection_matrix : Object3d.t -> unit
(** Rebuilds the projection from the current parameters; required after
    mutating them, matching three.js. *)

val update_matrices : ?force:bool -> Object3d.t -> unit
(** Refreshes world matrices and the inverse world matrix used as the view
    transform. Call once per frame before rendering through this camera -
    three.js does the same inside its Camera.updateMatrixWorld override. *)
