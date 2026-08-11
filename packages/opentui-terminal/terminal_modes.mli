(** Pure terminal mode transitions. A transition contains the next state and
    caller-owned ANSI bytes; it does not write to a terminal. *)

type screen = Main | Alternate
(** The active terminal screen. *)

type mouse_mode = Disabled | Buttons | Motion
(** The requested mouse tracking level. *)

type t
(** The terminal mode state. *)

type transition
(** A next state paired with output bytes. *)

val initial : t
(** [initial] is the default main-screen, visible-cursor state. *)

val next : transition -> t
(** [next transition] returns the state that follows [transition]. *)

val output : transition -> bytes
(** [output transition] returns a copy of the ANSI bytes for [transition]. *)

val screen : t -> screen
(** [screen state] returns the selected screen. *)

val cursor_visible : t -> bool
(** [cursor_visible state] reports cursor visibility. *)

val mouse_mode : t -> mouse_mode
(** [mouse_mode state] returns the mouse tracking level. *)

val bracketed_paste : t -> bool
(** [bracketed_paste state] reports bracketed-paste mode. *)

val set_screen : t -> screen -> transition
(** [set_screen state screen] returns a transition to [screen]. *)

val set_cursor_visible : t -> bool -> transition
(** [set_cursor_visible state visible] returns a cursor transition. *)

val set_mouse : t -> movement:bool -> transition
(** [set_mouse state ~movement] enables button or motion tracking. *)

val disable_mouse : t -> transition
(** [disable_mouse state] disables all supported mouse tracking modes. *)

val set_bracketed_paste : t -> bool -> transition
(** [set_bracketed_paste state enabled] returns a paste-mode transition. *)

val reset : t -> transition
(** [reset state] returns to {!initial} and emits the required cleanup
    sequences. *)
