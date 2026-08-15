(** Kitty keyboard protocol parser and progressive-enhancement flags. *)

val parse : bytes -> Key_decoder.decoded option

val build_flags :
  ?disambiguate:bool ->
  ?alternate_keys:bool ->
  ?events:bool ->
  ?all_keys_as_escapes:bool ->
  ?report_text:bool ->
  unit -> int

val push_sequence : flags:int -> bytes
val pop_sequence : bytes
