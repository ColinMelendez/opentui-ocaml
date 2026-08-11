type pointer_kind = Down | Up | Move | Drag | Scroll

type pointer_event = {
  kind : pointer_kind;
  button : int;
  x : int;
  y : int;
}

type propagation = Continue | Stop

type t
type error = Error.t

type render_status = Rendered | Skipped | Failed

type flush_result = {
  status : render_status;
  bytes_written : int32;
}

module Node : sig
  type t

  val id : t -> int
  val is_destroyed : t -> bool
  val is_dirty : t -> bool
  val children_count : t -> int

  val create_container :
    parent:t ->
    width:float ->
    height:float ->
    (t, error) result

  val create_text :
    parent:t ->
    width:float ->
    height:float ->
    text:string ->
    ?foreground:Opentui_native.Color.t ->
    ?background:Opentui_native.Color.t ->
    ?attributes:int32 ->
    unit ->
    (t, error) result

  val set_text : t -> text:string -> (unit, error) result
  val set_dimensions : t -> width:float -> height:float -> (unit, error) result

  val set_pointer_handler :
    t -> (t -> pointer_event -> propagation) -> (unit, error) result

  val clear_pointer_handler : t -> (unit, error) result
  val destroy : t -> (unit, error) result
end

type dispatch_result = Unhandled | Handled of Node.t

val create : width:int32 -> height:int32 -> (t, error) result
val root : t -> (Node.t, error) result
val resize : t -> width:int32 -> height:int32 -> (unit, error) result

val flush :
  t ->
  force:bool ->
  output:bytes ->
  (flush_result, error) result

val dispatch_pointer : t -> pointer_event -> (dispatch_result, error) result
val close : t -> unit
