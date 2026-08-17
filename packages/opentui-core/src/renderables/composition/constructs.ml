type child = Vnode.child

let generic ?id ?width ?height ?(focusable = false) ?render children =
  Vnode.h
    (fun context () ->
      Result.map V_renderable.as_renderable
        (V_renderable.create context ?id ?width ?height ~focusable ?render ()))
    () children

let box ?id ?background_color ?border_style ?border ?border_color ?should_fill
    children =
  Vnode.h
    (fun context () ->
      Result.map Box.as_renderable
        (Box.create context ?id ?background_color ?border_style ?border
           ?border_color ?should_fill ()))
    () children

let text ?id ?width_method ?wrap_mode ?content children =
  Vnode.h
    (fun context () ->
      Result.map Text.as_renderable
        (Text.create context ?id ?width_method ?wrap_mode ?content ()))
    () children

let code ?id ?content ?filetype ?syntax_style ?tree_sitter_client ?background ?wrap_mode
    ?conceal ?draw_unstyled_text ?streaming ?initial_styled_text ?base_highlight
    ?on_highlight ?on_chunks children =
  Vnode.h
    (fun context () ->
      Result.map Code.as_renderable
        (Code.create context ?id ?content ?filetype ?syntax_style
           ?tree_sitter_client ?background ?wrap_mode ?conceal ?draw_unstyled_text
           ?streaming ?initial_styled_text ?base_highlight ?on_highlight
           ?on_chunks ()))
    () children

let ascii_font ?id ?text ?font ?colors ?background_color children =
  Vnode.h
    (fun context () ->
      Result.map Ascii_font.as_renderable
        (Ascii_font.create context ?id ?text ?font ?colors ?background_color
           ()))
    () children

let input ?id ?value ?placeholder ?(focusable = true) children =
  Vnode.h
    (fun context () ->
      Result.map Input.as_renderable
        (Input.create context ?id ?value ?placeholder ~focusable ()))
    () children

let select ?id ?options ?selected_index ?font children =
  Vnode.h
    (fun context () ->
      Result.map Select.as_renderable
        (Select.create context ?id ?options ?selected_index ?font ()))
    () children

let tab_select ?id ?options ?tab_width children =
  Vnode.h
    (fun context () ->
      Result.map Tab_select.as_renderable
        (Tab_select.create context ?id ?options ?tab_width ()))
    () children

let frame_buffer ?id ~width ~height ?respect_alpha children =
  Vnode.h
    (fun context () ->
      Result.map Frame_buffer.as_renderable
        (Frame_buffer.create context ?id ~width ~height ?respect_alpha ()))
    () children

let scroll_box ?id ?(scroll_x = false) ?(scroll_y = true) ?width ?height
    children =
  Vnode.h
    (fun context () ->
      Result.map Scroll_box.as_renderable
        (Scroll_box.create context ?id ~scroll_x ~scroll_y ?width ?height ()))
    () children

module Vstyles = struct
  type input = Lib.Styled_text.stylable_input

  let styled_input ?fg ?bg ~attributes = function
    | Lib.Styled_text.Chunk value ->
        {
          value with
          fg = (match fg with Some _ -> fg | None -> value.fg);
          bg = (match bg with Some _ -> bg | None -> value.bg);
          attributes = value.attributes lor attributes;
        }
    | Lib.Styled_text.Text value ->
        Lib.Styled_text.chunk ?fg ?bg ~attributes value
    | Lib.Styled_text.Integer value ->
        Lib.Styled_text.chunk ?fg ?bg ~attributes (string_of_int value)
    | Lib.Styled_text.Boolean value ->
        Lib.Styled_text.chunk ?fg ?bg ~attributes (string_of_bool value)

  let styled ?(attributes = 0) ?fg ?bg values =
    Lib.Styled_text.create
      (List.map (styled_input ?fg ?bg ~attributes) values)

  let with_attributes attributes values = styled ~attributes values
  let bold values = with_attributes Lib.Text_attributes.bold values
  let italic values = with_attributes Lib.Text_attributes.italic values
  let underline values = with_attributes Lib.Text_attributes.underline values
  let dim values = with_attributes Lib.Text_attributes.dim values
  let blink values = with_attributes Lib.Text_attributes.blink values
  let inverse values = with_attributes Lib.Text_attributes.inverse values
  let hidden values = with_attributes Lib.Text_attributes.hidden values
  let strikethrough values =
    with_attributes Lib.Text_attributes.strikethrough values
  let bold_italic values =
    with_attributes
      (Lib.Text_attributes.bold lor Lib.Text_attributes.italic)
      values
  let bold_underline values =
    with_attributes
      (Lib.Text_attributes.bold lor Lib.Text_attributes.underline)
      values
  let italic_underline values =
    with_attributes
      (Lib.Text_attributes.italic lor Lib.Text_attributes.underline)
      values
  let bold_italic_underline values =
    with_attributes
      (Lib.Text_attributes.bold lor Lib.Text_attributes.italic
      lor Lib.Text_attributes.underline)
      values
  let color color values = styled ~fg:color values
  let bg_color color values = styled ~bg:color values
  let fg color values = styled ~fg:color values
  let bg color values = bg_color color values
end
