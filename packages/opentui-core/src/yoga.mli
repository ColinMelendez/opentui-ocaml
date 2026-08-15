(** Independent Yoga nodes used by retained renderables.

    A node is created independently, attached to a parent without changing
    its identity, detached without destruction, and explicitly freed when its
    owning renderable is destroyed. *)

type direction = Inherit | Ltr | Rtl
(** The direction used by {!Node.calculate_layout}. *)

type value = Undefined | Point of float | Percent of float | Auto
(** A Yoga style value. [Auto] is valid only for styles that accept it. *)

type edge =
  | Left
  | Top
  | Right
  | Bottom
  | Start
  | End
  | Horizontal
  | Vertical
  | All
(** A Yoga edge or edge group. *)

type gutter = Gutter_column | Gutter_row | Gutter_all
(** A Yoga gap axis. *)

type align =
  | Align_auto
  | Align_flex_start
  | Align_center
  | Align_flex_end
  | Align_stretch
  | Align_baseline
  | Align_space_between
  | Align_space_around
  | Align_space_evenly
(** A Yoga alignment value. *)

type box_sizing = Box_sizing_border_box | Box_sizing_content_box
(** A Yoga box-sizing value. *)

type display = Display_flex | Display_none | Display_contents
(** A Yoga display value. *)

type flex_direction =
  | Flex_column
  | Flex_column_reverse
  | Flex_row
  | Flex_row_reverse
(** A Yoga main-axis direction. *)

type justify =
  | Justify_flex_start
  | Justify_center
  | Justify_flex_end
  | Justify_space_between
  | Justify_space_around
  | Justify_space_evenly
(** A Yoga main-axis justification value. *)

type overflow = Overflow_visible | Overflow_hidden | Overflow_scroll
(** A Yoga overflow value. *)

type position_type = Position_static | Position_relative | Position_absolute
(** A Yoga positioning mode. *)

type wrap = Wrap_no_wrap | Wrap | Wrap_reverse
(** A Yoga flex-wrap value. *)

type layout = {
  left : float;
  top : float;
  right : float;
  bottom : float;
  width : float;
  height : float;
}
(** A copied computed layout in parent-relative coordinates. *)

module Node : sig
  type t
  (** An independently owned Yoga node. *)

  type nonrec value = value
  type nonrec edge = edge
  type nonrec gutter = gutter
  type nonrec align = align
  type nonrec box_sizing = box_sizing
  type nonrec display = display
  type nonrec flex_direction = flex_direction
  type nonrec justify = justify
  type nonrec overflow = overflow
  type nonrec position_type = position_type
  type nonrec wrap = wrap

  val create : unit -> (t, Native.Error.t) result
  val free : t -> (unit, Native.Error.t) result
  (** [free node] releases a detached node with no children. It does not
      release descendants. *)

  val free_recursive : t -> (unit, Native.Error.t) result
  (** [free_recursive node] releases a detached node and all of its
      descendants. *)

  val insert_child :
    parent:t -> child:t -> index:int32 -> (unit, Native.Error.t) result
  (** [insert_child] attaches a detached child without changing its native
      identity or releasing it. *)

  val remove_child : parent:t -> child:t -> (unit, Native.Error.t) result
  (** [remove_child] detaches a direct child without releasing it. *)
  val move_child :
    parent:t -> child:t -> index:int32 -> (unit, Native.Error.t) result
  val child_count : t -> (int32, Native.Error.t) result

  val calculate_layout :
    t -> width:float -> height:float -> direction:direction ->
    (unit, Native.Error.t) result

  val is_dirty : t -> (bool, Native.Error.t) result
  (** [is_dirty node] reads Yoga's native layout-invalidation flag. *)

  val mark_dirty : t -> (unit, Native.Error.t) result
  (** [mark_dirty node] requests remeasurement from the native measure owner. *)

  val has_new_layout : t -> (bool, Native.Error.t) result
  (** [has_new_layout node] reports whether Yoga has produced unseen layout. *)

  val mark_layout_seen : t -> (unit, Native.Error.t) result
  (** [mark_layout_seen node] acknowledges the node's computed layout. *)

  val set_width : t -> value -> (unit, Native.Error.t) result
  val set_height : t -> value -> (unit, Native.Error.t) result
  val set_min_width : t -> value -> (unit, Native.Error.t) result
  val set_min_height : t -> value -> (unit, Native.Error.t) result
  val set_max_width : t -> value -> (unit, Native.Error.t) result
  val set_max_height : t -> value -> (unit, Native.Error.t) result
  val set_flex_basis : t -> value -> (unit, Native.Error.t) result
  val set_margin : t -> edge:edge -> value -> (unit, Native.Error.t) result
  val set_padding : t -> edge:edge -> value -> (unit, Native.Error.t) result
  val set_position : t -> edge:edge -> value -> (unit, Native.Error.t) result
  val set_gap : t -> gutter:gutter -> value -> (unit, Native.Error.t) result

  val set_direction : t -> direction -> (unit, Native.Error.t) result
  val set_flex_direction : t -> flex_direction -> (unit, Native.Error.t) result
  val set_justify_content : t -> justify -> (unit, Native.Error.t) result
  val set_align_content : t -> align -> (unit, Native.Error.t) result
  val set_align_items : t -> align -> (unit, Native.Error.t) result
  val set_align_self : t -> align -> (unit, Native.Error.t) result
  val set_position_type : t -> position_type -> (unit, Native.Error.t) result
  val set_wrap : t -> wrap -> (unit, Native.Error.t) result
  val set_overflow : t -> overflow -> (unit, Native.Error.t) result
  val set_display : t -> display -> (unit, Native.Error.t) result
  val set_box_sizing : t -> box_sizing -> (unit, Native.Error.t) result

  val set_flex : t -> float option -> (unit, Native.Error.t) result
  val set_flex_grow : t -> float option -> (unit, Native.Error.t) result
  val set_flex_shrink : t -> float option -> (unit, Native.Error.t) result
  val set_aspect_ratio : t -> float option -> (unit, Native.Error.t) result
  val set_border :
    t -> edge:edge -> value:float option -> (unit, Native.Error.t) result

  val set_width_point : t -> float -> (unit, Native.Error.t) result
  val set_height_point : t -> float -> (unit, Native.Error.t) result
  val set_padding_point :
    t -> edge:edge -> value:float -> (unit, Native.Error.t) result

  val layout : t -> (layout, Native.Error.t) result
  (** [layout node] returns the most recently calculated layout. *)

  module Private : sig
    (** Internal access used by the native measurement adapter. *)
    val attach_native_renderable :
      t -> Opentui_raw.Native_renderable.t -> (unit, Native.Error.t) result
    val set_measure_func : t -> bool -> (unit, Native.Error.t) result
    val unset_measure_func : t -> (unit, Native.Error.t) result
    val has_measure_func : t -> (bool, Native.Error.t) result
    val native_pointer : t -> (Nativeint.t, Native.Error.t) result
  val set_measure_callback :
    (Nativeint.t * float * int32 * float * int32 -> float * float) -> unit
    val clear_measure_callback : unit -> unit
  end
end
