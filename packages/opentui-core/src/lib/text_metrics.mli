(** Small UTF-8 and display-column helpers shared by edit and view state. *)

type width_method = Wcwidth | Unicode

type codepoint = {
  byte_start : int;
  byte_end : int;
  code : int;
  width : int;
}

val code : codepoint -> int

val scan : ?tab_width:int -> width_method -> string -> codepoint array
val display_width : ?tab_width:int -> width_method -> string -> int
val byte_offset_at_display : ?tab_width:int -> width_method -> string -> int -> int
val display_offset_of_byte : ?tab_width:int -> width_method -> string -> int -> int
