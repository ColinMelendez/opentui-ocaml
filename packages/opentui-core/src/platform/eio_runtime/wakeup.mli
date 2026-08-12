(** Single-domain revision wakeups paired with a bounded event queue. *)
type t

val create : unit -> t
(** [create ()] creates a wakeup with revision [0]. *)

val revision : t -> int64
(** [revision wakeup] is the current wrapping revision. *)

val notify : t -> unit
(** [notify wakeup] increments the revision and wakes waiters. *)

val wait : t -> since:int64 -> int64
(** [wait wakeup ~since] blocks until the revision differs from [since]. *)

val push :
  t ->
  queue:Lib.Event_queue.t ->
  Lib.Event_queue.event ->
  (unit, Lib.Event_queue.error) result
(** [push] accepts an event into [queue] and notifies only after acceptance. *)
