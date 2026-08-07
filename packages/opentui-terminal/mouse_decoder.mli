type kind = Down | Up | Move | Drag | Scroll

type scroll_direction =
  | Scroll_up
  | Scroll_down
  | Scroll_left
  | Scroll_right

type modifiers = {
  shift : bool;
  alt : bool;
  ctrl : bool;
}

type scroll = {
  direction : scroll_direction;
  delta : int;
}

type event = {
  kind : kind;
  button : int;
  x : int;
  y : int;
  modifiers : modifiers;
  scroll : scroll option;
}

type t

val create : unit -> t
val reset : t -> unit
val decode : t -> Stdin_parser.event -> event option
