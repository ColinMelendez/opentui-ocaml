type camera_state = {
  mutable fov_degrees : float;
  mutable aspect : float;
  near : float;
  far : float;
}
(** Projection parameters owned by a perspective-camera node; changing them
    takes effect after {!Perspective_camera.update_projection_matrix},
    matching three.js. *)

type light_state = {
  color : Color.t;
  mutable intensity : float;
}

type point_state = {
  color : Color.t;
  mutable intensity : float;
  mutable distance : float;
}
(** Positional light parameters; [distance] is the falloff cutoff, zero or
    less meaning unlimited range. *)

type t = {
  mutable name : string option;
  mutable parent : t option;
  mutable children : t list;
  mutable visible : bool;
  position : Vector3.t;
  rotation : Euler.t;
  quaternion : Quaternion.t;
  scale : Vector3.t;
  up : Vector3.t;
  matrix : Matrix4.t;
  matrix_world : Matrix4.t;
  matrix_world_inverse : Matrix4.t;
  projection_matrix : Matrix4.t;
  mutable matrix_auto_update : bool;
  mutable matrix_world_auto_update : bool;
  mutable matrix_world_needs_update : bool;
  mutable synced_rotation : float * float * float;
  (** Bookkeeping for the lazy euler-to-quaternion sync; leave to the
      update path. *)
  mutable kind : kind;
}
(** One scene-graph node, the port of three.js Object3D for the supported
    node families. The transform fields are meant to be mutated directly
    ([node.position.x <- ...], [node.rotation.y <- ...]) exactly as the
    reference demos do.

    Rotation bookkeeping: [rotation] and [quaternion] are kept consistent at
    matrix-build time with last-write-wins semantics - writing euler angles
    re-derives the quaternion on the next update, while direct quaternion
    mutations (look_at, rotate_on_axis) survive until the euler angles change
    again. Reading one side immediately after mutating the other diverges
    from three.js's eager callbacks by design; anything that renders goes
    through the update path where they agree. *)

and kind =
  | Group
  | Scene_root
  | Mesh of Geometry.t * Material.t
  | Perspective_camera of camera_state
  | Directional_light of light_state * t
      (* The payload's second component is the light target node; its world
         position completes the light direction. *)
  | Point_light of point_state
  | Ambient_light of light_state

val make : ?name:string -> ?kind:kind -> unit -> t
(** A bare node with identity transform, visible, detached. [kind] defaults
    to {!Group}. *)

val name : t -> string option
val set_name : t -> string option -> unit

val parent : t -> t option

val children : t -> t list

val kind : t -> kind

val visible : t -> bool

val set_visible : t -> bool -> unit

val position : t -> Vector3.t

val rotation : t -> Euler.t

val quaternion : t -> Quaternion.t

val scale : t -> Vector3.t

val matrix : t -> Matrix4.t

val matrix_world : t -> Matrix4.t

val matrix_world_inverse : t -> Matrix4.t
(** Maintained by camera updates; meaningless for other node kinds. *)

val projection_matrix : t -> Matrix4.t
(** Maintained by camera updates; meaningless for other node kinds. *)

val add : t -> t -> unit
(** Re-parents [child] under [t], detaching it from any previous parent.
    Raises [Invalid_argument] when the link would create a cycle - adding a
    node to itself or to one of its own descendants. *)

val remove : t -> t -> unit

val remove_from_parent : t -> unit

val clear : t -> unit

val get_object_by_name : string -> t -> t option
(** Depth-first search of [t]'s subtree, excluding [t] itself unless it
    matches. *)

val traverse : (t -> unit) -> t -> unit
(** Pre-order visit of [t] and its whole subtree, ignoring visibility. *)

val update_matrix : t -> unit
(** Recomposes the local matrix from position/quaternion/scale when
    [matrix_auto_update] is on and flags the world matrix dirty, matching
    three.js updateMatrix. *)

val update_matrix_world : ?force:bool -> t -> unit
(** Port of three.js updateMatrixWorld: refresh local matrices, multiply
    parent world matrices downward while the dirty flag or [force]
    propagates, then recurse into children with auto-update enabled. *)

val update_world_matrix : parents:bool -> children:bool -> t -> unit
(** Port of three.js updateWorldMatrix: optionally refresh the ancestor
    chain, always refresh this node's local and world matrices, optionally
    refresh children. *)

val world_position : ?into:Vector3.t -> t -> Vector3.t
(** The node's world translation, updating ancestor matrices first. [into]
    avoids allocation. *)

val world_quaternion : ?into:Quaternion.t -> t -> Quaternion.t

val look_at : target:Vector3.t -> t -> unit
(** Orients the node so its +Z axis (cameras and directional lights: -Z)
    faces [target], matching three.js lookAt including parent-frame
    compensation through the parent's world rotation. *)

val rotate_on_axis : axis:Vector3.t -> angle:float -> t -> unit
(** Post-multiplies a local-space rotation about the normalized [axis].
    Deliberate divergence from three.js r177, which pre-compensates through
    the parent world quaternion: here the rotation composes on the right of
    the node's own quaternion in every frame, so the axis is always the
    node's own local space and parented nodes rotate identically to
    unparented ones. *)

val rotate_x : t -> float -> unit

val rotate_y : t -> float -> unit

val rotate_z : t -> float -> unit

val translate_on_axis : axis:Vector3.t -> distance:float -> t -> unit
(** Steps [position] along [axis] rotated into world space; [axis] must be
    normalized, matching three.js translateOnAxis. *)

val translate_x : t -> float -> unit

val translate_y : t -> float -> unit

val translate_z : t -> float -> unit
