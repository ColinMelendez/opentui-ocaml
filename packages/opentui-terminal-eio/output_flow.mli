(** Stateful Eio sink adapter for terminal bytes and mode transitions.

    Writes are retried for partial sink progress. A sink error poisons the
    adapter because terminal state may be uncertain; the sink itself is never
    closed by this module. *)

type error = Invalid_range | Flow_error | Desynchronized
(** Range, sink, and post-failure state errors. *)

type t
(** An output adapter with tracked terminal mode state. *)

val message : error -> string
(** [message error] is a diagnostic string for [error]. *)

val pp : Format.formatter -> error -> unit
(** [pp ppf error] formats [error]. *)

val create : sink:([> Eio.Flow.sink_ty] Eio.Resource.t) -> t
(** [create ~sink] creates an adapter without taking ownership of [sink]. *)

val screen : t -> Opentui_terminal.Terminal_modes.screen
(** [screen output] returns the tracked screen state. *)

val cursor_visible : t -> bool
(** [cursor_visible output] reports tracked cursor visibility. *)

val mouse_mode : t -> Opentui_terminal.Terminal_modes.mouse_mode
(** [mouse_mode output] returns tracked mouse mode. *)

val bracketed_paste : t -> bool
(** [bracketed_paste output] reports tracked paste mode. *)

val write : t -> bytes -> (unit, error) result
(** [write output bytes] writes all [bytes] or poisons [output] on failure. *)

val write_subbytes :
  t -> bytes:bytes -> off:int -> len:int -> (unit, error) result
(** [write_subbytes] writes exactly the validated subrange. *)

val set_screen :
  t -> Opentui_terminal.Terminal_modes.screen -> (unit, error) result
(** [set_screen] writes and commits a screen transition. *)

val set_cursor_visible : t -> bool -> (unit, error) result
(** [set_cursor_visible] writes and commits cursor visibility. *)

val set_mouse : t -> movement:bool -> (unit, error) result
(** [set_mouse] writes and commits mouse tracking. *)

val disable_mouse : t -> (unit, error) result
(** [disable_mouse] writes and commits mouse disablement. *)

val set_bracketed_paste : t -> bool -> (unit, error) result
(** [set_bracketed_paste] writes and commits bracketed-paste mode. *)

val reset : t -> (unit, error) result
(** [reset] writes and commits terminal cleanup state. *)
