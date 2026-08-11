(** Box renderables backed by an owner-scoped layout node.

    A box can fill its layout rectangle, draw a single-style border, or do
    both. The layout node and frame remain owned by their respective owners;
    this value only stores the box properties needed during a draw. *)

type border_style = No_border | Single | Double | Rounded | Heavy
(** The border glyph family. [No_border] draws no border glyphs. *)

type t
(** A mutable box renderable. *)

(** [create ~node] creates a box over [node]. The defaults are black
    background, [No_border], white border color, and no fill. *)
val create :
  node:Layout.Node.t ->
  ?background:Color.t ->
  ?border:border_style ->
  ?border_color:Color.t ->
  ?should_fill:bool ->
  unit ->
  t

(** [background box] is the current fill color. *)
val background : t -> Color.t

(** [set_background box ~background] changes the fill color. *)
val set_background : t -> background:Color.t -> unit

(** [border box] is the current border style. *)
val border : t -> border_style

(** [set_border box ~border] changes the border style. *)
val set_border : t -> border:border_style -> unit

(** [border_color box] is the current border foreground color. *)
val border_color : t -> Color.t

(** [set_border_color box ~border_color] changes the border foreground. *)
val set_border_color : t -> border_color:Color.t -> unit

(** [should_fill box] reports whether the layout rectangle is filled. *)
val should_fill : t -> bool

(** [set_should_fill box ~should_fill] changes whether the rectangle is filled. *)
val set_should_fill : t -> should_fill:bool -> unit

(** [draw box frame ~offset_x ~offset_y] draws the box at its computed layout
    position relative to the supplied parent origin. Coordinates and extents
    must fit the frame's checked cell boundary. *)
val draw :
  t ->
  Renderer.Frame.t ->
  offset_x:float ->
  offset_y:float ->
  (unit, Error.t) result
