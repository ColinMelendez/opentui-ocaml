type t

val of_raw : Opentui_raw.Text_buffer_view.t -> t
val raw : t -> Opentui_raw.Text_buffer_view.t
