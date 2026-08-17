(** Explicit time and cancellation capability used by Core services. *)

type timer

val fresh_timer : unit -> timer
(** [fresh_timer ()] creates a fresh opaque timer identity for a clock
    implementation. *)

val equal_timer : timer -> timer -> bool
(** [equal_timer left right] compares timer identities without exposing their
    representation. *)

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
