(** Standard terminal text attributes and their packed representation. *)

val none : int
val bold : int
val dim : int
val italic : int
val underline : int
val blink : int
val inverse : int
val hidden : int
val strikethrough : int

val of_flags :
  ?bold:bool ->
  ?dim:bool ->
  ?italic:bool ->
  ?underline:bool ->
  ?blink:bool ->
  ?inverse:bool ->
  ?hidden:bool ->
  ?strikethrough:bool -> unit -> int

val base : int -> int
