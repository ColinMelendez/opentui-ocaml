(** Text renderables backed by an owner-scoped layout node. *)
type t

(** [create ~node ~text] creates a renderable with copied text. *)
val create : node:Yoga.Node.t -> text:string -> t

(** [text renderable] returns the renderable's owned text. *)
val text : t -> string

(** [set_text renderable ~text] replaces the renderable's copied text. *)
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
  (unit, Native.Error.t) result
