(** Grid-rendered text tables backed by native text-buffer views. *)

type cell_content = Empty | Text of string | Styled of Lib.Styled_text.t
type content = cell_content list list
type alignment = Default | Left | Center | Right
type column_width_mode = Content | Full
type column_fitter = Proportional | Balanced

type t

val create :
  Render_context.t ->
  ?id:string ->
  ?content:content ->
  ?column_alignments:alignment list ->
  ?width_method:Text_buffer.width_method ->
  ?wrap_mode:Text_buffer_view.wrap_mode ->
  ?column_width_mode:column_width_mode ->
  ?column_fitter:column_fitter ->
  ?cell_padding:int ->
  ?cell_padding_x:int ->
  ?cell_padding_y:int ->
  ?column_gap:int ->
  ?show_borders:bool ->
  ?border:bool ->
  ?outer_border:bool ->
  ?selectable:bool ->
  ?selection_bg:Color.t ->
  ?selection_fg:Color.t ->
  ?border_style:Lib.Border.style ->
  ?border_color:Color.t ->
  ?border_background_color:Color.t ->
  ?background_color:Color.t ->
  ?fg:Color.t ->
  ?bg:Color.t ->
  ?attributes:int32 ->
  ?width:Yoga.value ->
  ?height:Yoga.value ->
  unit ->
  (t, Error.t) result

val as_renderable : t -> Renderable.t
val content : t -> content
val set_content : t -> content -> (unit, Error.t) result
val column_alignments : t -> alignment list
val set_column_alignments : t -> alignment list -> (unit, Error.t) result
val wrap_mode : t -> Text_buffer_view.wrap_mode
val set_wrap_mode : t -> Text_buffer_view.wrap_mode -> (unit, Error.t) result
val column_width_mode : t -> column_width_mode
val set_column_width_mode : t -> column_width_mode -> (unit, Error.t) result
val column_fitter : t -> column_fitter
val set_column_fitter : t -> column_fitter -> (unit, Error.t) result
val cell_padding : t -> int
val set_cell_padding : t -> int -> (unit, Error.t) result
val cell_padding_x : t -> int
val set_cell_padding_x : t -> int -> (unit, Error.t) result
val cell_padding_y : t -> int
val set_cell_padding_y : t -> int -> (unit, Error.t) result
val column_gap : t -> int
val set_column_gap : t -> int -> (unit, Error.t) result
val show_borders : t -> bool
val set_show_borders : t -> bool -> (unit, Error.t) result
val border : t -> bool
val set_border : t -> bool -> (unit, Error.t) result
val outer_border : t -> bool
val set_outer_border : t -> bool -> (unit, Error.t) result
val selectable : t -> bool
val set_selectable : t -> bool -> (unit, Error.t) result
val border_style : t -> Lib.Border.style
val set_border_style : t -> Lib.Border.style -> (unit, Error.t) result
val border_color : t -> Color.t
val set_border_color : t -> Color.t -> (unit, Error.t) result
val border_background_color : t -> Color.t
val set_border_background_color : t -> Color.t -> (unit, Error.t) result
val background_color : t -> Color.t
val set_background_color : t -> Color.t -> (unit, Error.t) result
val fg : t -> Color.t
val set_fg : t -> Color.t -> (unit, Error.t) result
val bg : t -> Color.t
val set_bg : t -> Color.t -> (unit, Error.t) result
val attributes : t -> int32
val set_attributes : t -> int32 -> (unit, Error.t) result
val has_selection : t -> (bool, Error.t) result
val selected_text : t -> (string, Error.t) result
val selection : t -> (Text_buffer_view.selection option, Error.t) result
val destroy : t -> unit
