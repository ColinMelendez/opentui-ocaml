(** The common retained object used by OpenTUI renderables. *)

type t
(** A retained layout/render object owned by one {!Render_context.t}. *)

type mouse_event_kind =
  | Down
  | Up
  | Move
  | Drag
  | Drag_end
  | Drop
  | Over
  | Out
  | Scroll

type mouse_event
(** A mutable pointer event routed through the retained renderable tree. *)

val mouse_kind : mouse_event -> mouse_event_kind
val mouse_button : mouse_event -> int
val mouse_x : mouse_event -> int
val mouse_y : mouse_event -> int
val mouse_modifiers : mouse_event -> Lib.Mouse_decoder.modifiers
val mouse_scroll : mouse_event -> Lib.Mouse_decoder.scroll option
val mouse_source : mouse_event -> t option
val mouse_target : mouse_event -> t option
val mouse_current_target : mouse_event -> t option
val mouse_is_dragging : mouse_event -> bool
val mouse_default_prevented : mouse_event -> bool
val mouse_stop_propagation : mouse_event -> unit
val mouse_prevent_default : mouse_event -> unit
val mouse_propagation_stopped : mouse_event -> bool

val id : t -> string
val set_id : t -> string -> (unit, Error.t) result
val num : t -> int
val context : t -> Render_context.t
val parent : t -> t option
val children : t -> t list
val child_count : t -> int
val find_child_by_id : t -> string -> t option
val find_descendant_by_id : t -> string -> t option

val is_destroyed : t -> bool
val is_dirty : t -> bool
val visible : t -> bool
val set_visible : t -> bool -> (unit, Error.t) result
val opacity : t -> float
val set_opacity : t -> float -> (unit, Error.t) result
val z_index : t -> int
val set_z_index : t -> int -> (unit, Error.t) result

val focusable : t -> bool
val set_focusable : t -> bool -> (unit, Error.t) result
val focused : t -> bool
val focus : t -> (unit, Error.t) result
val blur : t -> (unit, Error.t) result
val has_focused_descendant : t -> bool

(** These slots are invoked by the owning renderer's keyboard and pointer
    dispatchers. Passing [None] removes a slot. *)
val set_on_key_down :
  t -> (Lib.Key_handler.key_event -> unit) option -> (unit, Error.t) result

val set_on_key_release :
  t -> (Lib.Key_handler.key_event -> unit) option -> (unit, Error.t) result

val set_on_paste :
  t -> (Lib.Key_handler.paste_event -> unit) option -> (unit, Error.t) result

val set_on_mouse :
  t -> (mouse_event -> unit) option -> (unit, Error.t) result

val set_on_mouse_down :
  t -> (mouse_event -> unit) option -> (unit, Error.t) result

val set_on_mouse_up :
  t -> (mouse_event -> unit) option -> (unit, Error.t) result

val set_on_mouse_move :
  t -> (mouse_event -> unit) option -> (unit, Error.t) result

val set_on_mouse_drag :
  t -> (mouse_event -> unit) option -> (unit, Error.t) result

val set_on_mouse_drag_end :
  t -> (mouse_event -> unit) option -> (unit, Error.t) result

val set_on_mouse_drop :
  t -> (mouse_event -> unit) option -> (unit, Error.t) result

val set_on_mouse_over :
  t -> (mouse_event -> unit) option -> (unit, Error.t) result

val set_on_mouse_out :
  t -> (mouse_event -> unit) option -> (unit, Error.t) result

val set_on_mouse_scroll :
  t -> (mouse_event -> unit) option -> (unit, Error.t) result

val live : t -> bool
val set_live : t -> bool -> (unit, Error.t) result
val live_count : t -> int

val width : t -> float
val height : t -> float
val x : t -> float
val y : t -> float
val screen_x : t -> float
val screen_y : t -> float
val layout : t -> (Yoga.layout, Error.t) result

val request_render : t -> (unit, Error.t) result
val set_translate_x : t -> float -> (unit, Error.t) result
val set_translate_y : t -> float -> (unit, Error.t) result
val translate_x : t -> float
val translate_y : t -> float

val set_width : t -> Yoga.value -> (unit, Error.t) result
val set_height : t -> Yoga.value -> (unit, Error.t) result
val set_min_width : t -> Yoga.value -> (unit, Error.t) result
val set_min_height : t -> Yoga.value -> (unit, Error.t) result
val set_max_width : t -> Yoga.value -> (unit, Error.t) result
val set_max_height : t -> Yoga.value -> (unit, Error.t) result
val set_flex_basis : t -> Yoga.value -> (unit, Error.t) result
val set_margin : t -> edge:Yoga.edge -> Yoga.value -> (unit, Error.t) result
val set_padding : t -> edge:Yoga.edge -> Yoga.value -> (unit, Error.t) result
val set_position : t -> edge:Yoga.edge -> Yoga.value -> (unit, Error.t) result
val set_gap : t -> gutter:Yoga.gutter -> Yoga.value -> (unit, Error.t) result

val set_direction : t -> Yoga.direction -> (unit, Error.t) result
val set_flex_direction : t -> Yoga.flex_direction -> (unit, Error.t) result
val set_justify_content : t -> Yoga.justify -> (unit, Error.t) result
val set_align_content : t -> Yoga.align -> (unit, Error.t) result
val set_align_items : t -> Yoga.align -> (unit, Error.t) result
val set_align_self : t -> Yoga.align -> (unit, Error.t) result
val set_position_type : t -> Yoga.position_type -> (unit, Error.t) result
val set_wrap : t -> Yoga.wrap -> (unit, Error.t) result
val set_overflow : t -> Yoga.overflow -> (unit, Error.t) result
val set_display : t -> Yoga.display -> (unit, Error.t) result
val set_box_sizing : t -> Yoga.box_sizing -> (unit, Error.t) result

val set_flex : t -> float option -> (unit, Error.t) result
val set_flex_grow : t -> float option -> (unit, Error.t) result
val set_flex_shrink : t -> float option -> (unit, Error.t) result
val set_aspect_ratio : t -> float option -> (unit, Error.t) result
val set_border :
  t -> edge:Yoga.edge -> value:float option -> (unit, Error.t) result

val on_focused :
  t -> (unit -> unit) -> (Event_subscription.t, Error.t) result
val once_focused :
  t -> (unit -> unit) -> (Event_subscription.t, Error.t) result
val on_blurred :
  t -> (unit -> unit) -> (Event_subscription.t, Error.t) result
val once_blurred :
  t -> (unit -> unit) -> (Event_subscription.t, Error.t) result
val on_destroyed :
  t -> (unit -> unit) -> (Event_subscription.t, Error.t) result
val once_destroyed :
  t -> (unit -> unit) -> (Event_subscription.t, Error.t) result
val on_resized :
  t -> (unit -> unit) -> (Event_subscription.t, Error.t) result
val once_resized :
  t -> (unit -> unit) -> (Event_subscription.t, Error.t) result
val on_layout_changed :
  t -> (unit -> unit) -> (Event_subscription.t, Error.t) result
val once_layout_changed :
  t -> (unit -> unit) -> (Event_subscription.t, Error.t) result

val destroy : t -> unit
val destroy_recursively : t -> unit

module Private : sig
  type rect

  type behavior

  val make_behavior :
    ?on_update:(t -> float -> unit) ->
    ?on_resize:(t -> width:int -> height:int -> unit) ->
    ?on_remove:(t -> unit) ->
    ?lifecycle_pass:(t -> unit) ->
    ?key_press:(t -> Lib.Key_handler.key_event -> unit) ->
    ?key_release:(t -> Lib.Key_handler.key_event -> unit) ->
    ?paste:(t -> Lib.Key_handler.paste_event -> unit) ->
    ?mouse_event:(t -> mouse_event -> unit) ->
    ?render_before:(t -> Buffer.t -> float -> (unit, Error.t) result) ->
    ?render_self:(t -> Buffer.t -> float -> (unit, Error.t) result) ->
    ?render_after:(t -> Buffer.t -> float -> (unit, Error.t) result) ->
    ?render_replacement:(t -> Buffer.t -> float -> (unit, Error.t) result) ->
    ?scissor_rect:(t -> rect) ->
    ?visible_children:(t -> t list) ->
    ?destroy_self:(t -> unit) ->
    ?updates_each_frame:bool ->
    ?custom_scissor:bool ->
    ?filters_children:bool ->
    unit -> behavior

  val default_behavior : behavior

  val default_scissor_rect : t -> rect
  val inset_rect :
    rect ->
    left:float ->
    top:float ->
    right:float ->
    bottom:float ->
    rect

  val create :
    Render_context.t ->
    ?id:string ->
    ?behavior:behavior ->
    unit ->
    (t, Error.t) result

  val create_root : Render_context.t -> (t, Error.t) result
  val set_behavior : t -> behavior -> unit

  val with_yoga_node :
    t -> (Yoga.Node.t -> ('a, Error.t) result) -> ('a, Error.t) result

  val mark_yoga_dirty : t -> (unit, Error.t) result

  val attach :
    parent:t -> child:t -> index:int -> (int, Error.t) result
  val insert_before :
    parent:t -> child:t -> anchor:t -> (int, Error.t) result
  val detach : parent:t -> child:t -> (unit, Error.t) result

  val find_by_num : t -> int -> t option

  val make_mouse_event :
    kind:mouse_event_kind ->
    button:int ->
    x:int ->
    y:int ->
    modifiers:Lib.Mouse_decoder.modifiers ->
    scroll:Lib.Mouse_decoder.scroll option ->
    source:t option ->
    target:t option ->
    is_dragging:bool ->
    mouse_event

  val process_mouse_event : t -> mouse_event -> unit

  val resize_root : t -> width:int32 -> height:int32 -> (unit, Error.t) result
  val render_root :
    t -> Buffer.t -> delta_time:float -> (unit, Error.t) result
end
