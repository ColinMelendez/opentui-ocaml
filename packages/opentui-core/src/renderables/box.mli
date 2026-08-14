(** The retained layout container corresponding to OpenTUI's BoxRenderable. *)

type t
(** A typed Box value with a common retained renderable and layout children. *)

type border_sides = Lib.Border.sides
(** The normalized Yoga border sides used by a box. *)

val no_border : Lib.Border.border
val all_borders : Lib.Border.border

val create :
  Render_context.t ->
  ?id:string ->
  ?background_color:Color.t ->
  ?border_style:Lib.Border.style ->
  ?border:Lib.Border.border ->
  ?border_color:Color.t ->
  ?custom_border_chars:Lib.Border.characters ->
  ?should_fill:bool ->
  ?title:string ->
  ?title_color:Color.t ->
  ?title_alignment:Lib.Border.alignment ->
  ?bottom_title:string ->
  ?bottom_title_alignment:Lib.Border.alignment ->
  ?focused_border_color:Color.t ->
  ?focusable:bool ->
  ?gap:Yoga.value ->
  ?row_gap:Yoga.value ->
  ?column_gap:Yoga.value ->
  unit ->
  (t, Error.t) result
(** [create context ()] applies the reference Box defaults and options. *)

val as_renderable : t -> Renderable.t
(** [as_renderable box] exposes the common retained object for attachment. *)

val children : t -> Layout_children.t
(** [children box] exposes the box's physical layout-child capability. *)

val border : t -> Lib.Border.border
val border_sides : t -> border_sides
val border_style : t -> Lib.Border.style
val set_border : t -> Lib.Border.border -> (unit, Error.t) result
val set_border_style : t -> Lib.Border.style -> (unit, Error.t) result

val background_color : t -> Color.t
val set_background_color : t -> Color.t -> (unit, Error.t) result
val border_color : t -> Color.t
val set_border_color : t -> Color.t -> (unit, Error.t) result
val focused_border_color : t -> Color.t
val set_focused_border_color : t -> Color.t -> (unit, Error.t) result
val custom_border_chars : t -> Lib.Border.characters option
val set_custom_border_chars :
  t -> Lib.Border.characters option -> (unit, Error.t) result
val should_fill : t -> bool
val set_should_fill : t -> bool -> (unit, Error.t) result

val title : t -> string option
val set_title : t -> string option -> (unit, Error.t) result
val title_color : t -> Color.t option
val set_title_color : t -> Color.t option -> (unit, Error.t) result
val title_alignment : t -> Lib.Border.alignment
val set_title_alignment :
  t -> Lib.Border.alignment -> (unit, Error.t) result
val bottom_title : t -> string option
val set_bottom_title : t -> string option -> (unit, Error.t) result
val bottom_title_alignment : t -> Lib.Border.alignment
val set_bottom_title_alignment :
  t -> Lib.Border.alignment -> (unit, Error.t) result

val set_gap :
  t -> gutter:Yoga.gutter -> Yoga.value -> (unit, Error.t) result

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
