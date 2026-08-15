(** A retained cfonts-derived ASCII-art renderable. *)

type t

val create :
  Render_context.t ->
  ?id:string ->
  ?text:string ->
  ?font:Ascii_font_spec.name ->
  ?colors:Color.t list ->
  ?background_color:Color.t ->
  ?selection_bg:Color.t ->
  ?selection_fg:Color.t ->
  ?selectable:bool ->
  unit ->
  (t, Error.t) result

val as_renderable : t -> Renderable.t
val frame_buffer : t -> Owned_buffer.t
val text : t -> string
val set_text : t -> string -> (unit, Error.t) result
val font : t -> Ascii_font_spec.name
val set_font : t -> Ascii_font_spec.name -> (unit, Error.t) result
val colors : t -> Color.t list
val set_colors : t -> Color.t list -> (unit, Error.t) result
val background_color : t -> Color.t
val set_background_color : t -> Color.t -> (unit, Error.t) result
val selection_bg : t -> Color.t option
val set_selection_bg : t -> Color.t option -> (unit, Error.t) result
val selection_fg : t -> Color.t option
val set_selection_fg : t -> Color.t option -> (unit, Error.t) result
val selectable : t -> bool
val set_selectable : t -> bool -> (unit, Error.t) result
val selected_text : t -> string
val has_selection : t -> bool
val destroy : t -> unit
