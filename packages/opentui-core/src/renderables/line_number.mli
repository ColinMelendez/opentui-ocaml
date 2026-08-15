(** Line-number gutter composition for visual line metadata providers. *)

type line_sign = {
  before : string option;
  before_color : Color.t option;
  after : string option;
  after_color : Color.t option;
}

type line_color =
  | Color of Color.t
  | Config of { gutter : Color.t option; content : Color.t option }

type target = {
  renderable : Renderable.t;
  line_info : unit -> (Line_info.t, Error.t) result;
  virtual_line_count : unit -> int;
  scroll_y : unit -> int;
}

type t

val target_of_text_buffer_renderable :
  Text_buffer_renderable.t -> target
val target_of_code : Code.t -> target
val target_of_edit_buffer_renderable : Edit_buffer_renderable.t -> target
val target_of_textarea : Textarea.t -> target

val create :
  Render_context.t ->
  ?id:string ->
  ?target:target ->
  ?fg:Color.t ->
  ?bg:Color.t ->
  ?min_width:int ->
  ?padding_right:int ->
  ?line_colors:(int * line_color) list ->
  ?line_signs:(int * line_sign) list ->
  ?line_number_offset:int ->
  ?hide_line_numbers:int list ->
  ?line_numbers:(int * int) list ->
  ?show_line_numbers:bool ->
  unit ->
  (t, Error.t) result

val as_renderable : t -> Renderable.t
val target : t -> target option
val gutter : t -> Renderable.t option
val set_target : t -> target option -> (unit, Error.t) result
val clear_target : t -> (unit, Error.t) result
val show_line_numbers : t -> bool
val set_show_line_numbers : t -> bool -> (unit, Error.t) result
val fg : t -> Color.t
val set_fg : t -> Color.t -> (unit, Error.t) result
val bg : t -> Color.t
val set_bg : t -> Color.t -> (unit, Error.t) result
val set_line_color : t -> int -> line_color -> (unit, Error.t) result
val clear_line_color : t -> int -> (unit, Error.t) result
val clear_all_line_colors : t -> (unit, Error.t) result
val line_colors : t -> (int * line_color) list
val set_line_colors : t -> (int * line_color) list -> (unit, Error.t) result
val set_line_sign : t -> int -> line_sign -> (unit, Error.t) result
val clear_line_sign : t -> int -> (unit, Error.t) result
val line_signs : t -> (int * line_sign) list
val set_line_signs : t -> (int * line_sign) list -> (unit, Error.t) result
val clear_all_line_signs : t -> (unit, Error.t) result
val set_line_number : t -> int -> int -> (unit, Error.t) result
val clear_line_number : t -> int -> (unit, Error.t) result
val line_numbers : t -> (int * int) list
val set_line_numbers : t -> (int * int) list -> (unit, Error.t) result
val set_line_number_offset : t -> int -> (unit, Error.t) result
val line_number_offset : t -> int
val set_hide_line_numbers : t -> int list -> (unit, Error.t) result
val hide_line_numbers : t -> int list
val remeasure : t -> (unit, Error.t) result
val highlight_lines :
  t -> start_line:int -> end_line:int -> line_color -> (unit, Error.t) result
val clear_highlight_lines :
  t -> start_line:int -> end_line:int -> (unit, Error.t) result
val destroy : t -> unit
