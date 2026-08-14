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
