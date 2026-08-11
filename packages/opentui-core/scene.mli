(** Retained imperative scenes over {!Opentui_native.Renderer} and Yoga.

    A scene owns its renderer and layout tree. Nodes keep stable identities
    until they are destroyed, and [flush] is the controlled boundary that
    calculates layout and renders caller-owned output bytes. Closing a scene
    invalidates the scene and all of its nodes. *)

(** {1:types Types} *)

type pointer_kind = Down | Up | Move | Drag | Scroll
(** Pointer propagation kinds reported to handlers. *)

type pointer_event = {
  kind : pointer_kind;
  button : int;
  x : int;
  y : int;
}
(** A pointer event in scene coordinates. [x] and [y] are integer cell
    coordinates; [button] identifies the native or synthesized button. *)

type propagation = Continue | Stop
(** A pointer handler's decision to continue bubbling or stop propagation. *)

type t
(** A scene owner. *)

type error = Error.t
(** The error type returned by scene operations. *)

type render_status = Rendered | Skipped | Failed
(** The outcome of a native frame attempt. *)

type flush_result = {
  status : render_status;
  bytes_written : int32;
}
(** A flush outcome. On [Rendered], [bytes_written] is the defined prefix
    length in the caller-owned buffer supplied to [flush]. A skipped or failed
    outcome reports zero bytes. *)

module Node : sig
  (** Nodes owned by a {!t}. A destroyed node can still be queried with
      {!id}, {!is_destroyed}, {!is_dirty}, and {!children_count}; mutating
      operations return an error. *)
  type t

  (** [id node] is the stable identity of [node] within its scene. *)
  val id : t -> int

  (** [is_destroyed node] is [true] after [node] or an ancestor is destroyed,
      or after its scene is closed. *)
  val is_destroyed : t -> bool

  (** [is_dirty node] reports whether [node] has changed since the last
      successful rendered or skipped flush. *)
  val is_dirty : t -> bool

  (** [children_count node] is the number of currently attached children. *)
  val children_count : t -> int

  (** [create_container ~parent ~width ~height] attaches a fixed-size
      container to a live container parent. *)
  val create_container :
    parent:t ->
    width:float ->
    height:float ->
    (t, error) result

  (** [create_text ... ~text] attaches a text node. The text is copied at
      construction, so the caller may reuse its input string. *)
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

  (** [set_text node ~text] replaces a text node's copied contents and marks
      it dirty. *)
  val set_text : t -> text:string -> (unit, error) result

  (** [set_dimensions node ...] changes the node's fixed dimensions and marks
      its scene layout dirty. *)
  val set_dimensions : t -> width:float -> height:float -> (unit, error) result

  (** [set_pointer_handler node handler] installs the handler used by
      {!dispatch_pointer}. Handler exceptions propagate to the caller. *)
  val set_pointer_handler :
    t -> (t -> pointer_event -> propagation) -> (unit, error) result

  (** [clear_pointer_handler node] removes the node's pointer handler. *)
  val clear_pointer_handler : t -> (unit, error) result

  (** [destroy node] recursively detaches and destroys [node] and its
      descendants. The scene root cannot be destroyed. *)
  val destroy : t -> (unit, error) result
end

type dispatch_result = Unhandled | Handled of Node.t
(** The result of pointer hit-testing and handler propagation. *)

(** {1:constructors Constructors and lifecycle} *)

(** [create ~width ~height] creates a scene with a fixed render size. *)
val create : width:int32 -> height:int32 -> (t, error) result

(** [root scene] returns the live scene root. *)
val root : t -> (Node.t, error) result

(** [resize scene ...] resizes the native renderer and schedules a layout
    recalculation. *)
val resize : t -> width:int32 -> height:int32 -> (unit, error) result

(** [flush scene ~force ~output] calculates dirty layout, draws the scene, and
    writes resolved characters into the caller-owned [output] bytes. A clean
    scene is skipped unless [force] is [true]. On a rendered result only the
    reported prefix is defined; a failed attempt leaves the scene dirty. *)
val flush :
  t ->
  force:bool ->
  output:bytes ->
  (flush_result, error) result

(** [dispatch_pointer scene event] hit-tests [event] against the latest layout
    and bubbles handlers from the target toward the root. *)
val dispatch_pointer : t -> pointer_event -> (dispatch_result, error) result

(** [close scene] releases native resources and invalidates the scene and all
    nodes. It is idempotent. *)
val close : t -> unit
