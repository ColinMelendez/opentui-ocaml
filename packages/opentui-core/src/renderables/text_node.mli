(** Non-layout text composition nodes used by {!Text}. *)

type style = {
  fg : Color.t option;
  bg : Color.t option;
  attributes : int;
  link : string option;
}
(** Style values inherited by descendant text. *)

type t
(** A retained text-composition node without a Yoga node. *)

type child =
  | Text_string of string
  | Text_node of t
(** A value stored by a text node after insertion. *)

type input =
  | String of string
  | Node of t
  | Styled of Lib.Styled_text.t
(** A value accepted by text-child insertion. Styled text expands into nodes. *)

val create :
  ?id:string ->
  ?fg:Color.t ->
  ?bg:Color.t ->
  ?attributes:int ->
  ?link:string ->
  unit ->
  t
(** [create ()] creates a detached text node. *)

val id : t -> string
val parent : t -> t option
val children : t -> child list
val child_count : t -> int
val get_children : t -> t list
val find_child_by_id : t -> string -> t option
val is_dirty : t -> bool

val add : ?index:int -> t -> input -> (int, Error.t) result
(** [add parent input] inserts text, a node, or styled text. *)

val insert_before :
  t -> input -> anchor:t -> (unit, Error.t) result
(** [insert_before parent input ~anchor] inserts before a direct node child. *)

val remove : t -> t -> (unit, Error.t) result
(** [remove parent child] detaches a direct node child without destroying it. *)

val clear : t -> unit
(** [clear node] removes all children and clears their parent links. *)

val merge_style : t -> style -> style
(** [merge_style node inherited] resolves [node]'s style over [inherited]. *)

val gather : ?inherited:style -> t -> Lib.Styled_text.t
(** [gather node] collects leaf strings with inherited styles and marks the
    visited nodes clean. *)

val fg : t -> Color.t option
val set_fg : t -> Color.t option -> unit
val bg : t -> Color.t option
val set_bg : t -> Color.t option -> unit
val attributes : t -> int
val set_attributes : t -> int -> unit
val link : t -> string option
val set_link : t -> string option -> unit

module Private : sig
  val create_root : ?id:string -> on_change:(unit -> unit) -> unit -> t
  val discard_children : t -> unit
end
