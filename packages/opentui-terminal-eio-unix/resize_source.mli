(** Single-domain Unix [SIGWINCH] ownership for Eio terminal runtimes.
    At most one source is installed in the process. The signal only records a
    pending notification; callers perform the size query separately. *)

type error =
  | Already_installed
  | Existing_handler
  | Closed
(** Installation and lifecycle errors. *)

type t
(** An owned resize signal source. *)

val message : error -> string
(** [message error] is a diagnostic string for [error]. *)

val pp : Format.formatter -> error -> unit
(** [pp ppf error] formats [error]. *)

val create : sw:Eio.Switch.t -> unit -> (t, error) result
(** [create ~sw ()] installs the source and restores the previous signal
    behavior when [sw] releases. *)

val wait : t -> (unit, error) result
(** [wait source] waits for one pending resize notification. *)

val close : t -> unit
(** [close source] restores the previous signal behavior. It is idempotent. *)
