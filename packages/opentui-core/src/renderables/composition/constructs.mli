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

val code :
  ?id:string ->
  ?content:string ->
  ?filetype:string ->
  ?syntax_style:Syntax_style.t ->
  ?tree_sitter_client:Lib.Tree_sitter_client.t ->
  ?background:Platform.Eio_runtime.Background.submitter ->
  ?wrap_mode:Text_buffer_view.wrap_mode ->
  ?conceal:bool ->
  ?draw_unstyled_text:bool ->
  ?streaming:bool ->
  ?initial_styled_text:Lib.Styled_text.t ->
  ?base_highlight:string ->
  ?on_highlight:
    (Lib.Tree_sitter_types.highlight list ->
    (Lib.Tree_sitter_types.highlight list, Lib.Tree_sitter_types.parser_error)
    result) ->
  ?on_chunks:
    (Lib.Styled_text.t ->
    (Lib.Styled_text.t, Lib.Tree_sitter_types.parser_error) result) ->
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
  ?font:Ascii_font_spec.name ->
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

module Vstyles : sig
  type input = Lib.Styled_text.stylable_input

  val styled :
    ?attributes:int ->
    ?fg:Color.t ->
    ?bg:Color.t ->
    input list ->
    Lib.Styled_text.t

  val bold : input list -> Lib.Styled_text.t
  val italic : input list -> Lib.Styled_text.t
  val underline : input list -> Lib.Styled_text.t
  val dim : input list -> Lib.Styled_text.t
  val blink : input list -> Lib.Styled_text.t
  val inverse : input list -> Lib.Styled_text.t
  val hidden : input list -> Lib.Styled_text.t
  val strikethrough : input list -> Lib.Styled_text.t
  val bold_italic : input list -> Lib.Styled_text.t
  val bold_underline : input list -> Lib.Styled_text.t
  val italic_underline : input list -> Lib.Styled_text.t
  val bold_italic_underline : input list -> Lib.Styled_text.t
  val color : Color.t -> input list -> Lib.Styled_text.t
  val bg_color : Color.t -> input list -> Lib.Styled_text.t
  val fg : Color.t -> input list -> Lib.Styled_text.t
  val bg : Color.t -> input list -> Lib.Styled_text.t
end
