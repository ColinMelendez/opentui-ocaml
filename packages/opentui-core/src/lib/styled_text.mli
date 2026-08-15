(** Styled text chunks used by the text-composition tree. *)

type chunk = {
  text : string;
  fg : Color.t option;
  bg : Color.t option;
  attributes : int;
  link : string option;
}
(** A text segment and the style inherited by that segment. *)

type t
(** An ordered sequence of styled text chunks. *)

type style_attrs = {
  fg : Color.t option;
  bg : Color.t option;
  bold : bool;
  italic : bool;
  underline : bool;
  strikethrough : bool;
  dim : bool;
  reverse : bool;
  blink : bool;
  hidden : bool;
}

type stylable_input = Text of string | Integer of int | Boolean of bool | Chunk of chunk

val chunk :
  ?fg:Color.t ->
  ?bg:Color.t ->
  ?attributes:int ->
  ?link:string ->
  string ->
  chunk
(** [chunk text] creates one styled segment. *)

val create : chunk list -> t
(** [create chunks] preserves [chunks] in order. *)

val of_string : string -> t
(** [of_string text] creates one unstyled segment. *)

val chunks : t -> chunk list
(** [chunks text] returns the ordered segments. *)

val plain_text : t -> string
(** [plain_text text] concatenates the segment text without style data. *)

val is_empty : t -> bool
val append : t -> t -> t
val map : (chunk -> chunk) -> t -> t
val style_attrs :
  ?fg:Color.t ->
  ?bg:Color.t ->
  ?bold:bool ->
  ?italic:bool ->
  ?underline:bool ->
  ?strikethrough:bool ->
  ?dim:bool ->
  ?reverse:bool ->
  ?blink:bool ->
  ?hidden:bool ->
  unit -> style_attrs
val apply_style : stylable_input -> style_attrs -> chunk
val string_to_styled_text : string -> t
val link : string -> stylable_input -> chunk
val fg : Color.t -> stylable_input -> chunk
val bg : Color.t -> stylable_input -> chunk
val bold : stylable_input -> chunk
val italic : stylable_input -> chunk
val underline : stylable_input -> chunk
val strikethrough : stylable_input -> chunk
val dim : stylable_input -> chunk
val reverse : stylable_input -> chunk
val blink : stylable_input -> chunk
val hidden : stylable_input -> chunk

val black : stylable_input -> chunk
val red : stylable_input -> chunk
val green : stylable_input -> chunk
val yellow : stylable_input -> chunk
val blue : stylable_input -> chunk
val magenta : stylable_input -> chunk
val cyan : stylable_input -> chunk
val white : stylable_input -> chunk
val bright_black : stylable_input -> chunk
val bright_red : stylable_input -> chunk
val bright_green : stylable_input -> chunk
val bright_yellow : stylable_input -> chunk
val bright_blue : stylable_input -> chunk
val bright_magenta : stylable_input -> chunk
val bright_cyan : stylable_input -> chunk
val bright_white : stylable_input -> chunk
val bg_black : stylable_input -> chunk
val bg_red : stylable_input -> chunk
val bg_green : stylable_input -> chunk
val bg_yellow : stylable_input -> chunk
val bg_blue : stylable_input -> chunk
val bg_magenta : stylable_input -> chunk
val bg_cyan : stylable_input -> chunk
val bg_white : stylable_input -> chunk

val template : strings:string list -> values:stylable_input list -> t
