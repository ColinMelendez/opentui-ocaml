type t

val of_raw : Opentui_raw.Text_buffer.t -> t
val raw : t -> Opentui_raw.Text_buffer.t
