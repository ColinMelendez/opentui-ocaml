(** A retained renderable backed by native text storage and measurement. *)

type t
(** Text storage, a text view, and a native Yoga measure owner sharing one
    retained renderable. *)

val create :
  Render_context.t ->
  ?id:string ->
  ?width_method:Text_buffer.width_method ->
  ?wrap_mode:Text_buffer_view.wrap_mode ->
  ?selectable:bool ->
  ?scrollable:bool ->
  unit ->
  (t, Error.t) result
(** [create context ()] creates a text-buffer renderable with an attached
    native measure target. *)

val as_renderable : t -> Renderable.t

(** [text_buffer] returns the owned storage used by the renderable. Mutating
    the returned value directly does not invalidate Yoga; use [set_text],
    [append], or [clear] when changing text through this renderable. *)
val text_buffer : t -> Text_buffer.t

(** [text_buffer_view] returns the owned measurement view. Changes made
    directly to the view do not invalidate Yoga; use the renderable's wrapping
    operations when changing its measurement configuration. *)
val text_buffer_view : t -> Text_buffer_view.t

val set_text : t -> string -> (unit, Error.t) result
val append : t -> string -> (unit, Error.t) result
val clear : t -> (unit, Error.t) result
val set_styled_text : t -> Lib.Styled_text.t -> (unit, Error.t) result
val text : t -> (string, Error.t) result
val styled_text : t -> (Lib.Styled_text.t option, Error.t) result

val set_default_fg : t -> Color.t option -> (unit, Error.t) result
val default_fg : t -> (Color.t option, Error.t) result
val set_default_bg : t -> Color.t option -> (unit, Error.t) result
val default_bg : t -> (Color.t option, Error.t) result
val set_default_attributes : t -> int option -> (unit, Error.t) result
val default_attributes : t -> (int option, Error.t) result
val reset_defaults : t -> (unit, Error.t) result
val set_syntax_style : t -> Syntax_style.t option -> (unit, Error.t) result
val syntax_style : t -> (Syntax_style.t option, Error.t) result
val set_tab_width : t -> int -> (unit, Error.t) result
val tab_width : t -> (int, Error.t) result

val set_selection :
  t -> start:int -> end_:int -> ?bg_color:Color.t -> ?fg_color:Color.t -> unit -> (unit, Error.t) result
val update_selection :
  t -> end_:int -> ?bg_color:Color.t -> ?fg_color:Color.t -> unit -> (unit, Error.t) result
val reset_selection : t -> (unit, Error.t) result
val selected_text : t -> (string, Error.t) result
val set_local_selection :
  t -> anchor_x:int -> anchor_y:int -> focus_x:int -> focus_y:int ->
  ?bg_color:Color.t -> ?fg_color:Color.t -> unit -> (bool, Error.t) result
val update_local_selection :
  t -> anchor_x:int -> anchor_y:int -> focus_x:int -> focus_y:int ->
  ?bg_color:Color.t -> ?fg_color:Color.t -> unit -> (bool, Error.t) result
val reset_local_selection : t -> (unit, Error.t) result
val set_tab_indicator : t -> string -> (unit, Error.t) result
val set_tab_indicator_color : t -> Color.t -> (unit, Error.t) result
val set_truncate : t -> bool -> (unit, Error.t) result

val wrap_mode : t -> Text_buffer_view.wrap_mode
val scroll_x : t -> int
val scroll_y : t -> int
val set_wrap_mode : t -> Text_buffer_view.wrap_mode -> (unit, Error.t) result
val set_first_line_offset : t -> int -> (unit, Error.t) result
val set_viewport_size : t -> width:int -> height:int -> (unit, Error.t) result
val set_viewport :
  t -> x:int -> y:int -> width:int -> height:int -> (unit, Error.t) result
val set_scroll : t -> x:int -> y:int -> (unit, Error.t) result

val line_info : t -> (Text_buffer_view.line_info, Error.t) result
val logical_line_info : t -> (Text_buffer_view.line_info, Error.t) result
val virtual_line_count : t -> (int, Error.t) result

val measure_for_dimensions :
  t -> width:int32 -> height:int32 -> (Text_buffer_view.measure, Error.t) result

val destroy : t -> unit

module Private : sig
  (** Install the lifecycle callback used by a concrete text renderable. *)
  val set_lifecycle_pass : t -> (unit -> unit) option -> unit
end
