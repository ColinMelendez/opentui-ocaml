module Border = Lib.Border

type border_sides = Border.sides

type t = {
  renderable : Renderable.t;
  children : Layout_children.t;
  mutable border : Border.border;
  mutable border_sides : border_sides;
  mutable border_style : Border.style;
  mutable background_color : Color.t;
  mutable border_color : Color.t;
  mutable focused_border_color : Color.t;
  mutable custom_border_chars : Border.characters option;
  mutable should_fill : bool;
  mutable title : string option;
  mutable title_color : Color.t option;
  mutable title_alignment : Border.alignment;
  mutable bottom_title : string option;
  mutable bottom_title_alignment : Border.alignment;
}

let no_border = Border.no_border
let all_borders = Border.all_borders

let apply_border_sides renderable sides =
  let set edge enabled =
    Renderable.set_border renderable ~edge
      ~value:(Some (if enabled then 1.0 else 0.0))
  in
  match set Yoga.Left (Border.left sides) with
  | Error error -> Error error
  | Ok () ->
      (match set Yoga.Top (Border.top sides) with
      | Error error -> Error error
      | Ok () ->
          (match set Yoga.Right (Border.right sides) with
          | Error error -> Error error
          | Ok () -> set Yoga.Bottom (Border.bottom sides)))

let set_and_request box setter value =
  match Renderable.request_render box.renderable with
  | Error error -> Error error
  | Ok () ->
      setter value;
      Ok ()

let scissor_rect box renderable =
  let sides = box.border_sides in
  Renderable.Private.inset_rect
    (Renderable.Private.default_scissor_rect renderable)
    ~left:(if Border.left sides then 1.0 else 0.0)
    ~top:(if Border.top sides then 1.0 else 0.0)
    ~right:(if Border.right sides then 1.0 else 0.0)
    ~bottom:(if Border.bottom sides then 1.0 else 0.0)

let render_self box renderable buffer _delta_time =
  let sides = box.border_sides in
  let has_border =
    Border.left sides || Border.top sides || Border.right sides
    || Border.bottom sides
  in
  let _, _, _, background_alpha = Color.channels box.background_color in
  let has_visible_fill = box.should_fill && background_alpha > 0 in
  if not has_border && not has_visible_fill then Ok ()
  else
    let has_focus_within =
      Renderable.focusable renderable
      && (Renderable.focused renderable
         || Renderable.has_focused_descendant renderable)
    in
    let border_color =
      if has_focus_within then box.focused_border_color else box.border_color
    in
    let title_color = Option.value box.title_color ~default:border_color in
    let border_chars =
      Option.value box.custom_border_chars
        ~default:(Border.characters box.border_style)
    in
    Buffer.draw_box buffer
      ~x:(Int32.of_float (Renderable.screen_x renderable))
      ~y:(Int32.of_float (Renderable.screen_y renderable))
      ~width:(Int32.of_float (Renderable.width renderable))
      ~height:(Int32.of_float (Renderable.height renderable))
      ~border_chars:(Border.Private.to_native border_chars)
      ~packed_options:
        (Border.Private.pack_draw_options ~border:box.border
           ~should_fill:box.should_fill ~title_alignment:box.title_alignment
           ~bottom_title_alignment:box.bottom_title_alignment)
      ~border_color ~background_color:box.background_color ~title_color
      ~title:box.title ~bottom_title:box.bottom_title

let create context ?id ?background_color ?border_style ?border ?border_color
    ?custom_border_chars ?should_fill ?title ?title_color ?title_alignment
    ?bottom_title ?bottom_title_alignment ?focused_border_color ?focusable
    ?gap ?row_gap ?column_gap () =
  let border_style_value = Option.value border_style ~default:Border.Single in
  let has_border_supporting_option =
    Option.is_some border_style
    || Option.is_some border_color
    || Option.is_some focused_border_color
    || Option.is_some custom_border_chars
  in
  let border_value =
    match border with
    | Some Border.No_border when has_border_supporting_option ->
        Border.All_borders
    | Some value -> value
    | None when has_border_supporting_option ->
        Border.All_borders
    | None -> Border.No_border
  in
  let background_color = Option.value background_color ~default:Color.transparent in
  let border_color = Option.value border_color ~default:Color.white in
  let focused_border_color =
    match focused_border_color with
    | Some color -> Ok color
    | None -> Color.rgba ~red:0 ~green:170 ~blue:255 ~alpha:255
  in
  match focused_border_color with
  | Error error -> Error (Error.Native error)
  | Ok focused_border_color ->
      (match Renderable.Private.create context ?id () with
      | Error error -> Error error
      | Ok renderable ->
          let box =
            {
              renderable;
              children = Layout_children.Private.of_renderable renderable;
              border = border_value;
              border_sides = Border.to_sides border_value;
              border_style = border_style_value;
              background_color;
              border_color;
              focused_border_color;
              custom_border_chars;
              should_fill = Option.value should_fill ~default:true;
              title;
              title_color;
              title_alignment = Option.value title_alignment ~default:Border.Left;
              bottom_title;
              bottom_title_alignment =
                Option.value bottom_title_alignment ~default:Border.Left;
            }
          in
          let behavior =
            Renderable.Private.make_behavior
              ~render_self:(render_self box)
              ~scissor_rect:(scissor_rect box)
              ~custom_scissor:true ()
          in
          Renderable.Private.set_behavior renderable behavior;
          let configure result operation =
            match result with
            | Error error -> Error error
            | Ok () -> operation ()
          in
          let result =
            configure (apply_border_sides renderable box.border_sides) (fun () ->
                match focusable with
                | None | Some false -> Ok ()
                | Some true -> Renderable.set_focusable renderable true)
          in
          let result =
            configure result (fun () ->
                match gap with
                | None -> Ok ()
                | Some value ->
                    Renderable.set_gap renderable ~gutter:Yoga.Gutter_all value)
          in
          let result =
            configure result (fun () ->
                match row_gap with
                | None -> Ok ()
                | Some value ->
                    Renderable.set_gap renderable ~gutter:Yoga.Gutter_row value)
          in
          let result =
            configure result (fun () ->
                match column_gap with
                | None -> Ok ()
                | Some value ->
                    Renderable.set_gap renderable ~gutter:Yoga.Gutter_column
                      value)
          in
          (match result with
          | Ok () -> Ok box
          | Error error ->
              Renderable.destroy renderable;
              Error error))

let as_renderable box = box.renderable
let children box = box.children
let border box = box.border
let border_sides box = box.border_sides
let border_style box = box.border_style
let background_color box = box.background_color
let border_color box = box.border_color
let focused_border_color box = box.focused_border_color
let custom_border_chars box = box.custom_border_chars
let should_fill box = box.should_fill
let title box = box.title
let title_color box = box.title_color
let title_alignment box = box.title_alignment
let bottom_title box = box.bottom_title
let bottom_title_alignment box = box.bottom_title_alignment

let set_border box value =
  let previous = box.border_sides in
  let next = Border.to_sides value in
  match apply_border_sides box.renderable next with
  | Error error ->
      ignore (apply_border_sides box.renderable previous);
      Error error
  | Ok () ->
      box.border <- value;
      box.border_sides <- next;
      Ok ()

let ensure_border box =
  match box.border with
  | Border.No_border ->
      let value = Border.All_borders in
      let sides = Border.to_sides value in
      (match apply_border_sides box.renderable sides with
      | Error error -> Error error
      | Ok () ->
          box.border <- value;
          box.border_sides <- sides;
          Ok ())
  | Border.All_borders | Border.Sides _ -> Ok ()

let set_border_style box value =
  match ensure_border box with
  | Error error -> Error error
  | Ok () ->
      box.border_style <- value;
      box.custom_border_chars <- None;
      Renderable.request_render box.renderable

let set_background_color box value =
  set_and_request box (fun next -> box.background_color <- next) value

let set_border_color box value =
  match ensure_border box with
  | Error error -> Error error
  | Ok () -> set_and_request box (fun next -> box.border_color <- next) value

let set_focused_border_color box value =
  match ensure_border box with
  | Error error -> Error error
  | Ok () ->
      set_and_request box (fun next -> box.focused_border_color <- next) value

let set_custom_border_chars box value =
  set_and_request box (fun next -> box.custom_border_chars <- next) value

let set_should_fill box value =
  set_and_request box (fun next -> box.should_fill <- next) value

let set_title box value = set_and_request box (fun next -> box.title <- next) value

let set_title_color box value =
  set_and_request box (fun next -> box.title_color <- next) value

let set_title_alignment box value =
  set_and_request box (fun next -> box.title_alignment <- next) value

let set_bottom_title box value =
  set_and_request box (fun next -> box.bottom_title <- next) value

let set_bottom_title_alignment box value =
  set_and_request box (fun next -> box.bottom_title_alignment <- next) value

let set_gap box ~gutter value = Renderable.set_gap box.renderable ~gutter value

let width box = Renderable.width box.renderable
let height box = Renderable.height box.renderable
let set_width box value = Renderable.set_width box.renderable value
let set_height box value = Renderable.set_height box.renderable value

let visible box = Renderable.visible box.renderable
let set_visible box value = Renderable.set_visible box.renderable value
let opacity box = Renderable.opacity box.renderable
let set_opacity box value = Renderable.set_opacity box.renderable value
let z_index box = Renderable.z_index box.renderable
let set_z_index box value = Renderable.set_z_index box.renderable value

let focusable box = Renderable.focusable box.renderable
let set_focusable box value = Renderable.set_focusable box.renderable value
let focus box = Renderable.focus box.renderable
let blur box = Renderable.blur box.renderable
let destroy box = Renderable.destroy box.renderable
let destroy_recursively box = Renderable.destroy_recursively box.renderable
