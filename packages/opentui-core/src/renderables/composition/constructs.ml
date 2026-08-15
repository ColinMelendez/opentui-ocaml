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

let select ?id ?options ?selected_index children =
  Vnode.h
    (fun context () ->
      Result.map Select.as_renderable
        (Select.create context ?id ?options ?selected_index ()))
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
