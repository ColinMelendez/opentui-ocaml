(** The three.js-shaped scene graph API of opentui-three.

    Modules mirror the reference naming so demos port nearly
    line-for-line. Rendering and cell conversion live behind the
    renderer modules that land with the three-renderer phases. *)

module Color = Color

module Euler = Euler

module Matrix4 = Matrix4
(** Column-major storage; see individual operations for aliasing rules. *)

module Quaternion = Quaternion

module Vector3 = Vector3
