(** Scroll-wheel acceleration policies. *)

type t

val linear : unit -> t
val macos : ?a:float -> ?tau:float -> ?max_multiplier:float -> unit -> t
val tick : t -> ?now_ms:float -> unit -> float
val reset : t -> unit
