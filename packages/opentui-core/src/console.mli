(** An owner-local diagnostic console rendered as a terminal overlay.

    The upstream console can capture and replace the process-global
    JavaScript console.  This port deliberately exposes explicit append
    operations instead: an application may bridge its own logging source, and
    destroying a console never mutates global process state. *)

type level = Log | Info | Warn | Error | Debug
type position = Top | Bottom | Left | Right
type mouse_action = Mouse_down | Mouse_drag | Mouse_up

type entry = {
  sequence : int64;
  level : level;
  message : string;
}

type display_line = {
  text : string;
  level : level;
}

type bounds = {
  x : int;
  y : int;
  width : int;
  height : int;
}

type t

val create :
  width:int ->
  height:int ->
  ?position:position ->
  ?size_percent:int ->
  ?max_stored_logs:int ->
  ?max_display_lines:int ->
  ?title:string ->
  unit -> (t, Error.t) result

val append : t -> level -> string -> (unit, Error.t) result
val log : t -> string -> (unit, Error.t) result
val info : t -> string -> (unit, Error.t) result
val warn : t -> string -> (unit, Error.t) result
val error : t -> string -> (unit, Error.t) result
val debug : t -> string -> (unit, Error.t) result

val entries : t -> (entry list, Error.t) result
val display_lines : t -> (display_line list, Error.t) result
val bounds : t -> (bounds, Error.t) result
val position : t -> (position, Error.t) result
val size_percent : t -> (int, Error.t) result
val visible : t -> (bool, Error.t) result
val focused : t -> (bool, Error.t) result

val show : t -> (unit, Error.t) result
val hide : t -> (unit, Error.t) result
val toggle : t -> (unit, Error.t) result
val focus : t -> (unit, Error.t) result
val blur : t -> (unit, Error.t) result
val clear : t -> (unit, Error.t) result

val resize : t -> width:int -> height:int -> (unit, Error.t) result
val set_position : t -> position -> (unit, Error.t) result
val set_size_percent : t -> int -> (unit, Error.t) result

val scroll_top : t -> (int, Error.t) result
val scroll_up : t -> (unit, Error.t) result
val scroll_down : t -> (unit, Error.t) result
val scroll_to_top : t -> (unit, Error.t) result
val scroll_to_bottom : t -> (unit, Error.t) result

val select :
  t ->
  start_line:int ->
  start_column:int ->
  end_line:int ->
  end_column:int ->
  (unit, Error.t) result
val clear_selection : t -> (unit, Error.t) result
val has_selection : t -> (bool, Error.t) result
val selected_text : t -> (string, Error.t) result

val handle_mouse :
  t -> action:mouse_action -> button:int -> x:int -> y:int ->
  (bool, Error.t) result

val render : t -> Buffer.t -> (unit, Error.t) result
val destroy : t -> unit
val is_destroyed : t -> bool
