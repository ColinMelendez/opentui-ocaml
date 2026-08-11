(** Scoped raw-mode terminal ownership over a caller-owned descriptor and
    {!Opentui_terminal_eio.Output_flow.t}.

    The session never closes either resource. Restoration retries only the
    output or termios steps that previously failed. *)

type error =
  | Unix_error of Unix.error * string * string
  | Output_error of Opentui_terminal_eio.Output_flow.error
  | Output_and_unix_error of
      Opentui_terminal_eio.Output_flow.error
      * Unix.error
      * string
      * string
  | Closed
(** Terminal, output, and lifecycle errors. *)

type t
(** A saved terminal configuration and restoration scope. *)

val message : error -> string
(** [message error] is a diagnostic string for [error]. *)

val pp : Format.formatter -> error -> unit
(** [pp ppf error] formats [error]. *)

val create :
  sw:Eio.Switch.t ->
  fd:Eio_unix.Fd.t ->
  output:Opentui_terminal_eio.Output_flow.t ->
  (t, error) result
(** [create ...] snapshots the descriptor's termios state and registers a
    best-effort switch-release restoration hook. *)

val enter : t -> (unit, error) result
(** [enter session] applies raw input settings. Repeated entry is harmless. *)

val restore : t -> (unit, error) result
(** [restore session] resets output modes and restores termios state. *)

val close : t -> unit
(** [close session] performs best-effort restoration. *)

val is_entered : t -> bool
(** [is_entered session] is [true] only while raw mode is active. *)
