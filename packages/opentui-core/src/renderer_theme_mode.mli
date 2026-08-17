type mode = Light | Dark

type response = { handled : bool; changed_mode : mode option }
type waiter
type t

val create : clock:Lib.Clock.t -> query:(unit -> unit) -> unit -> t
val create_without_clock : query:(unit -> unit) -> unit -> t
val mode : t -> mode option
val request : t -> unit
val handle_sequence : t -> string -> response
(** [wait_for] invokes [on_result] immediately and returns a cancelled waiter
    when a positive timeout is requested without a clock. After [dispose], it
    returns an inert cancelled waiter without invoking the callback. Callers
    that need to report unsupported timed waits should use the renderer-facing
    API. *)
val wait_for : t -> timeout_ms:int -> on_result:(mode option -> unit) -> waiter
val cancel_wait : t -> waiter -> unit
val cancel_refresh : t -> unit
val dispose : t -> unit
(** [dispose] cancels and detaches all waiters without invoking callbacks. *)
val query_sequence : string
val mode_name : mode -> string
