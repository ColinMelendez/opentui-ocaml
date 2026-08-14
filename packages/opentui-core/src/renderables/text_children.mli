(** Typed access to a {!Text_node} composition tree. *)

type t
(** The child-attachment capability of one text root or text node. *)

type child = Text_node.input =
  | String of string
  | Node of Text_node.t
  | Styled of Lib.Styled_text.t

val add : ?index:int -> t -> child -> (int, Error.t) result
val remove : t -> Text_node.t -> (unit, Error.t) result
val insert_before :
  t -> child -> anchor:Text_node.t -> (unit, Error.t) result
val children : t -> Text_node.t list
val child_count : t -> int
val clear : t -> unit

module Private : sig
  val of_node : Text_node.t -> t
end
