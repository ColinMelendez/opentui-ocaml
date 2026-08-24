(** The scene root: the node a renderer draws, port of three.js Scene for
    the supported feature set (background color is a renderer concern and
    arrives through the clear color). *)

val create : ?name:string -> unit -> Object3d.t
