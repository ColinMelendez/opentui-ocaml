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

  val set_width : t -> float -> (unit, Error.t) result
  val set_height : t -> float -> (unit, Error.t) result
  val layout : t -> (layout, Error.t) result
end

val create : unit -> (t, Error.t) result
val close : t -> unit
val root : t -> (Node.t, Error.t) result

val add_child :
  t -> parent:Node.t -> (Node.t, Error.t) result

val calculate :
  t ->
  width:float ->
  height:float ->
  direction:direction ->
  (unit, Error.t) result
