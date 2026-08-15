(** Terminal OSC palette query planning, response parsing, and fallback colors.

    The module is transport-neutral: a terminal session writes the query bytes
    and feeds response fragments back to {!feed}. *)

type colors = {
  palette : string option array;
  default_foreground : string option;
  default_background : string option;
  cursor_color : string option;
  mouse_foreground : string option;
  mouse_background : string option;
  tek_foreground : string option;
  tek_background : string option;
  highlight_background : string option;
  highlight_foreground : string option;
}

type normalized = {
  palette : Rgba.t array;
  default_foreground : Rgba.t;
  default_background : Rgba.t;
}

type t

val create : ?size:int -> unit -> t
val feed : t -> string -> unit
val colors : t -> colors
val complete : t -> bool

val palette_query : ?size:int -> unit -> string
val special_query : ?is_tmux:bool -> unit -> string
val osc_support_query : unit -> string
val wrap_for_legacy_tmux : string -> string

val normalize : colors option -> normalized
val fallback : unit -> normalized
