type t

val create : node:Layout.Node.t -> text:string -> t
val text : t -> string
val set_text : t -> text:string -> unit

(** [draw ... ~offset_x ~offset_y] adds the caller-owned parent origin to the
    node's local Yoga origin before checked conversion to frame coordinates. *)
val draw :
  t ->
  Renderer.Frame.t ->
  offset_x:float ->
  offset_y:float ->
  foreground:Color.t ->
  background:Color.t ->
  attributes:int32 ->
  (unit, Error.t) result
