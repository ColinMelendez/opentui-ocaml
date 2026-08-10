type error = Invalid_range | Flow_error | Desynchronized

type t

val message : error -> string
val pp : Format.formatter -> error -> unit

val create : sink:([> Eio.Flow.sink_ty] Eio.Resource.t) -> t

val screen : t -> Opentui_terminal.Terminal_modes.screen
val cursor_visible : t -> bool
val mouse_mode : t -> Opentui_terminal.Terminal_modes.mouse_mode
val bracketed_paste : t -> bool

val write : t -> bytes -> (unit, error) result

val write_subbytes :
  t -> bytes:bytes -> off:int -> len:int -> (unit, error) result

val set_screen :
  t -> Opentui_terminal.Terminal_modes.screen -> (unit, error) result

val set_cursor_visible : t -> bool -> (unit, error) result
val set_mouse : t -> movement:bool -> (unit, error) result
val disable_mouse : t -> (unit, error) result
val set_bracketed_paste : t -> bool -> (unit, error) result
val reset : t -> (unit, error) result
