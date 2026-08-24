(** Lambertian diffuse response to directional and ambient light, the port of
    three.js MeshLambertMaterial for the phase-1 light set. *)

val create : ?color:Color.t -> unit -> Material.t
(** [color] defaults to white, matching the reference. *)
