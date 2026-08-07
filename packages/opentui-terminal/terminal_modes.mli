type screen = Main | Alternate
type mouse_mode = Disabled | Buttons | Motion

type t
type transition

val initial : t
val next : transition -> t
val output : transition -> bytes

val screen : t -> screen
val cursor_visible : t -> bool
val mouse_mode : t -> mouse_mode
val bracketed_paste : t -> bool

val set_screen : t -> screen -> transition
val set_cursor_visible : t -> bool -> transition
val set_mouse : t -> movement:bool -> transition
val disable_mouse : t -> transition
val set_bracketed_paste : t -> bool -> transition
val reset : t -> transition
