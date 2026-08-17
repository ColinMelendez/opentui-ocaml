(** Owner-domain monotonic time and one-shot timers backed by Eio. *)

type t

val create :
  sw:Eio.Switch.t -> mono_clock:_ Eio.Time.Mono.t -> t
(** [create] binds the adapter to [sw]. Timer fibers and their callbacks run
    in the switch's owning Eio domain. *)

val lib_clock : t -> Lib.Clock.t
(** [lib_clock] exposes the adapter through the portable Core clock
    capability. *)

val owns_lib_clock : t -> Lib.Clock.t -> bool
(** [owns_lib_clock clock value] reports whether [value] is the cached
    capability returned by [lib_clock clock]. *)

val now : t -> float
(** [now] is monotonic time in seconds relative to adapter creation. *)

val sleep_until : t -> deadline:float -> unit
(** [sleep_until] waits for a relative monotonic deadline. *)

val close : t -> unit
(** [close] idempotently cancels all pending timers. *)
