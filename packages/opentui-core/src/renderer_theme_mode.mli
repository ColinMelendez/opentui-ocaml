type mode = Light | Dark

type response = { handled : bool; changed_mode : mode option }
type waiter
type t

val create : clock:Lib.Clock.t -> query:(unit -> unit) -> unit -> t
val mode : t -> mode option
val request : t -> unit
val handle_sequence : t -> string -> response
val wait_for : t -> timeout_ms:int -> on_result:(mode option -> unit) -> waiter
val cancel_wait : t -> waiter -> unit
val cancel_refresh : t -> unit
val dispose : t -> unit
val query_sequence : string
val mode_name : mode -> string
