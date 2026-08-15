(** Explicit time and cancellation capability used by Core services. *)

type timer

type t

val create :
  now:(unit -> float) ->
  schedule:(delay:float -> (unit -> unit) -> timer) ->
  cancel:(timer -> unit) ->
  t

val now : t -> float
val schedule : t -> delay:float -> (unit -> unit) -> timer
val cancel : t -> timer -> unit

type manual

val manual : unit -> manual
val manual_clock : manual -> t
val set : manual -> float -> unit
val advance : manual -> float -> unit
val run_due : manual -> unit
