(** Owner-domain monotonic time and one-shot timers backed by Eio. *)

type t

type error = Closed | Wrong_domain | Switch_mismatch

val message : error -> string
val pp : Format.formatter -> error -> unit

val create :
  sw:Eio.Switch.t -> mono_clock:_ Eio.Time.Mono.t -> t
(** [create] binds the adapter to [sw]. Timer fibers and their callbacks run
    in the switch's owning Eio domain. *)

val owns_domain : t -> bool
(** [owns_domain clock] reports whether the current domain is the domain in
    which [clock] was created. *)

val owns_switch : t -> Eio.Switch.t -> bool
(** [owns_switch clock sw] checks exact switch identity. *)

val check_owner : t -> (unit, error) result
(** [check_owner] validates that the clock is open and called from its owner
    domain. *)

val check : t -> sw:Eio.Switch.t -> (unit, error) result
(** [check clock ~sw] additionally validates exact switch affinity. *)

val lib_clock : t -> Lib.Clock.t
(** [lib_clock] exposes the adapter through the portable Core clock
    capability. Creating or retrieving it and invoking its scheduling
    callbacks are owner-domain operations. Wrong-domain use raises
    [Invalid_argument] because the portable callback surface cannot carry an
    affinity error; use {!check_owner} for structured admission. *)

val owns_lib_clock : t -> Lib.Clock.t -> bool
(** [owns_lib_clock clock value] reports whether [value] is the cached
    capability returned by [lib_clock clock]. It is an owner-domain
    operation. *)

val now : t -> float
(** [now] is monotonic time in seconds relative to adapter creation. It fails
    loudly on wrong-domain or closed-clock programmer misuse; callers crossing
    an Eio domain boundary can use {!check_owner} for structured admission. *)

val sleep_until : t -> deadline:float -> unit
(** [sleep_until] waits for a relative monotonic deadline on the owner domain
    and fails loudly on affinity or lifetime misuse. *)

val close : t -> (unit, error) result
(** [close] idempotently cancels all pending timers when called from the owner
    domain, and returns [Wrong_domain] without mutation otherwise. The owning
    switch also closes the clock when it is released. *)
