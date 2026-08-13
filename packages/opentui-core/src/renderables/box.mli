(** The retained layout container corresponding to OpenTUI's BoxRenderable. *)

type t
(** A typed Box value with a common retained renderable and layout children. *)

type border_sides = {
  left : bool;
  top : bool;
  right : bool;
  bottom : bool;
}
(** The four Yoga border sides used by a box. *)

val no_border : border_sides
val all_borders : border_sides

val create : Render_context.t -> ?id:string -> unit -> (t, Error.t) result
(** [create context ()] creates a layout-only box with no border. A box with
    an active border requires the later Buffer drawing surface and returns
    [Error.Unsupported] when rendered until that surface is available. *)

val as_renderable : t -> Renderable.t
(** [as_renderable box] exposes the common retained object for attachment. *)

val children : t -> Layout_children.t
(** [children box] exposes the box's physical layout-child capability. *)

val border : t -> border_sides
val set_border : t -> border_sides -> (unit, Error.t) result

val set_gap :
  t -> gutter:Yoga.gutter -> Yoga.value -> (unit, Error.t) result
(** [set_gap box ~gutter value] applies a Yoga gap to the box. *)

val width : t -> float
val height : t -> float
val set_width : t -> Yoga.value -> (unit, Error.t) result
val set_height : t -> Yoga.value -> (unit, Error.t) result

val visible : t -> bool
val set_visible : t -> bool -> (unit, Error.t) result
val opacity : t -> float
val set_opacity : t -> float -> (unit, Error.t) result
val z_index : t -> int
val set_z_index : t -> int -> (unit, Error.t) result

val focusable : t -> bool
val set_focusable : t -> bool -> (unit, Error.t) result
val focus : t -> (unit, Error.t) result
val blur : t -> (unit, Error.t) result
val destroy : t -> unit
val destroy_recursively : t -> unit
