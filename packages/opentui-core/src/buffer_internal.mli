type t

val of_raw : Opentui_raw.Buffer.t -> t
val raw : t -> Opentui_raw.Buffer.t
