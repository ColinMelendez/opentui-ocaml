(** Retained imperative scenes over {!Renderer} and {!Yoga}.

    A scene owns its renderer and layout tree. Nodes keep stable identities
    until they are destroyed, and [flush] is the controlled boundary that
    calculates layout and renders caller-owned output bytes. Closing a scene
    invalidates the scene and all of its nodes. *)

(** {1:types Types} *)

type border_style =
  Renderables.Box.border_style =
  | No_border
  | Single
  | Double
  | Rounded
  | Heavy
(** The border styles supported by {!Box}. *)

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

  type kind = Box | Text
  (** The retained renderable family of a node. *)

  (** [kind node] is the renderable family of [node]. *)
  val kind : t -> kind

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

  (** [move_to_index node ~index] moves [node] to the zero-based position
      [index] among its parent's children in render order. The node and its
      descendants keep their identities. The root cannot be moved. *)
  val move_to_index : t -> index:int -> (unit, error) result

  (** [create_box ...] attaches a styled box to a live Box parent. *)
  val create_box :
    parent:t ->
    width:float ->
    height:float ->
    ?background:Color.t ->
    ?border:border_style ->
    ?border_color:Color.t ->
    ?should_fill:bool ->
    unit ->
    (t, error) result

  (** [create_text ... ~text] attaches a text node. The text is copied at
      construction, so the caller may reuse its input string. *)
  val create_text :
    parent:t ->
    width:float ->
    height:float ->
    text:string ->
    ?foreground:Color.t ->
    ?background:Color.t ->
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

module Box : sig
  (** Typed access to an OpenTUI-shaped retained box. *)
  type t

  (** [create ...] attaches a box to [parent]. *)
  val create :
    parent:Node.t ->
    width:float ->
    height:float ->
    ?background:Color.t ->
    ?border:border_style ->
    ?border_color:Color.t ->
    ?should_fill:bool ->
    unit ->
    (t, error) result

  (** [node box] exposes the common retained node for child operations and
      generic event registration. *)
  val node : t -> Node.t

  (** [background box] is the current fill color. *)
  val background : t -> Color.t

  (** [set_background box ~background] changes the fill color and invalidates
      the scene. *)
  val set_background :
    t -> background:Color.t -> (unit, error) result

  (** [border box] is the current border style. *)
  val border : t -> border_style

  (** [set_border box ~border] changes the border style and invalidates the
      scene. *)
  val set_border : t -> border:border_style -> (unit, error) result

  (** [border_color box] is the current border foreground color. *)
  val border_color : t -> Color.t

  (** [set_border_color box ~border_color] changes the border color and
      invalidates the scene. *)
  val set_border_color :
    t -> border_color:Color.t -> (unit, error) result

  (** [should_fill box] reports whether the box fills its rectangle. *)
  val should_fill : t -> bool

  (** [set_should_fill box ~should_fill] changes filling and invalidates the
      scene. *)
  val set_should_fill : t -> should_fill:bool -> (unit, error) result
end

module Text : sig
  (** Typed access to an OpenTUI-shaped retained plain-text renderable. *)
  type t

  (** [create ...] attaches copied text to [parent]. *)
  val create :
    parent:Node.t ->
    width:float ->
    height:float ->
    text:string ->
    ?foreground:Color.t ->
    ?background:Color.t ->
    ?attributes:int32 ->
    unit ->
    (t, error) result

  (** [node text] exposes the common retained node for generic operations. *)
  val node : t -> Node.t

  (** [content text] is the renderable's copied text. *)
  val content : t -> string

  (** [foreground text] is the current text foreground color. *)
  val foreground : t -> Color.t

  (** [background text] is the current text background color. *)
  val background : t -> Color.t

  (** [attributes text] is the current text attribute bitset. *)
  val attributes : t -> int32

  (** [set text ~content] replaces copied content and invalidates the scene. *)
  val set : t -> content:string -> (unit, error) result

  (** [set_foreground text ~foreground] changes the text foreground. *)
  val set_foreground :
    t -> foreground:Color.t -> (unit, error) result

  (** [set_background text ~background] changes the text background. *)
  val set_background :
    t -> background:Color.t -> (unit, error) result

  (** [set_attributes text ~attributes] changes text attributes. *)
  val set_attributes : t -> attributes:int32 -> (unit, error) result
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
