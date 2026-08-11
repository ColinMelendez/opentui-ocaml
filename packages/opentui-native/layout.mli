type direction = Inherit | Ltr | Rtl

type layout = {
  left : float;
  top : float;
  right : float;
  bottom : float;
  width : float;
  height : float;
}

type t

module Node : sig
  type t

  val set_dimensions : t -> width:float -> height:float -> (unit, Error.t) result
  val layout : t -> (layout, Error.t) result
end

val create : unit -> (t, Error.t) result
val close : t -> unit
val root : t -> (Node.t, Error.t) result
val add_child : parent:Node.t -> (Node.t, Error.t) result
val remove_child : parent:Node.t -> child:Node.t -> (unit, Error.t) result

val calculate :
  t ->
  width:float ->
  height:float ->
  direction:direction ->
  (unit, Error.t) result
