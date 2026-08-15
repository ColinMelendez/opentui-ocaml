(** Reference cfonts-derived ASCII font definitions and rasterization helpers. *)

type name = Tiny | Block | Shade | Slick | Huge | Grid | Pallet

type definition = {
  name : string;
  lines : int;
  letterspace_size : int;
  colors : int;
}

type measure = { width : int; height : int }

val font_names : name list
val name_of_string : string -> name option
val string_of_name : name -> string
val definition : name -> definition
val glyph : name -> char -> string array option
val measure_text : ?font:name -> string -> measure
val character_positions : ?font:name -> string -> int array
val coordinate_to_character_index : ?font:name -> int -> string -> int

val render_to_frame_buffer :
  Owned_buffer.t ->
  ?text:string ->
  ?x:int ->
  ?y:int ->
  ?colors:Color.t list ->
  ?background_color:Color.t ->
  ?font:name ->
  unit ->
  (measure, Error.t) result
