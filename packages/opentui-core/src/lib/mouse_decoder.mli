(** Stateful decoding of complete SGR and X10 mouse protocol frames. *)

type kind = Down | Up | Move | Drag | Scroll
(** Mouse event classification. *)

type scroll_direction =
  | Scroll_up
  | Scroll_down
  | Scroll_left
  | Scroll_right
(** Scroll direction reported by a mouse event. *)

type modifiers = {
  shift : bool;
  alt : bool;
  ctrl : bool;
}
(** Modifier flags reported by a mouse event. *)

type scroll = {
  direction : scroll_direction;
  delta : int;
}
(** A scroll direction and signed amount. *)

type event = {
  kind : kind;
  button : int;
  x : int;
  y : int;
  modifiers : modifiers;
  scroll : scroll option;
}
(** A decoded mouse event in terminal cell coordinates. *)

type t
(** Mouse-button state used to classify motion as drag. *)

(** [create ()] creates a fresh mouse decoder. *)
val create : unit -> t

(** [reset decoder] clears pressed-button state. *)
val reset : t -> unit

(** [decode decoder input] returns [Some event] for a mouse frame and [None]
    for other parser events. *)
val decode : t -> Stdin_parser.event -> event option
