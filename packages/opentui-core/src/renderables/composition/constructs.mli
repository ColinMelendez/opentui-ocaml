(** Typed constructors corresponding to the reference composition helpers. *)

type child = Vnode.child

val generic :
  ?id:string ->
  ?width:Yoga.value ->
  ?height:Yoga.value ->
  ?focusable:bool ->
  ?render:V_renderable.render ->
  child list ->
  Vnode.t

val box :
  ?id:string ->
  ?background_color:Color.t ->
  ?border_style:Lib.Border.style ->
  ?border:Lib.Border.border ->
  ?border_color:Color.t ->
  ?should_fill:bool ->
  child list ->
  Vnode.t

val text :
  ?id:string ->
  ?width_method:Text_buffer.width_method ->
  ?wrap_mode:Text_buffer_view.wrap_mode ->
  ?content:Lib.Styled_text.t ->
  child list ->
  Vnode.t

val ascii_font :
  ?id:string ->
  ?text:string ->
  ?font:Ascii_font_spec.name ->
  ?colors:Color.t list ->
  ?background_color:Color.t ->
  child list ->
  Vnode.t

val input :
  ?id:string ->
  ?value:string ->
  ?placeholder:string ->
  ?focusable:bool ->
  child list ->
  Vnode.t

val select :
  ?id:string ->
  ?options:Select.option_item list ->
  ?selected_index:int ->
  child list ->
  Vnode.t

val tab_select :
  ?id:string ->
  ?options:Tab_select.option_item list ->
  ?tab_width:int ->
  child list ->
  Vnode.t

val frame_buffer :
  ?id:string ->
  width:int ->
  height:int ->
  ?respect_alpha:bool ->
  child list ->
  Vnode.t

val scroll_box :
  ?id:string ->
  ?scroll_x:bool ->
  ?scroll_y:bool ->
  ?width:Yoga.value ->
  ?height:Yoga.value ->
  child list ->
  Vnode.t
