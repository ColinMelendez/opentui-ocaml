(** Linear-space RGB color with three.js conversion semantics. *)

type t = { mutable r : float; mutable g : float; mutable b : float }
(** Channels live in linear working space. *)

val create : ?r:float -> ?g:float -> ?b:float -> unit -> t
val copy : t -> t -> unit
val set_rgb : t -> float -> float -> float -> unit

val from_hex_int : int -> t
(** Treats the integer as sRGB bytes (0xRRGGBB) and converts to linear
    working space through the standard transfer function. *)
