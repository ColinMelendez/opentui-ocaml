type t

val create : clock:Clock.t -> unit -> t
val debounce : t -> id:string -> delay:float -> (unit -> unit) -> unit
val cancel : t -> id:string -> unit
val clear : t -> unit
val size : t -> int
