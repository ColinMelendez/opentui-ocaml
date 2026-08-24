(** Unlit surface color, the port of three.js MeshBasicMaterial. *)

val create : ?color:Color.t -> unit -> Material.t
(** [color] defaults to white, matching the reference. *)
