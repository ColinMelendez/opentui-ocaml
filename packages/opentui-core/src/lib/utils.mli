(** Portable helpers that do not own a renderer or terminal process. *)

val create_text_attributes :
  ?bold:bool ->
  ?italic:bool ->
  ?underline:bool ->
  ?dim:bool ->
  ?blink:bool ->
  ?inverse:bool ->
  ?hidden:bool ->
  ?strikethrough:bool ->
  unit ->
  int

val pack_link : link_id:int -> attributes:int -> int
val unpack_link : int -> int * int

val visualize_tree :
  root:'a ->
  children:('a -> 'a list) ->
  label:('a -> string) ->
  string
