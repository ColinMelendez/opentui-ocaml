(* Port of vendor/opentui/packages/examples/src/simple-layout-example.ts.

   Cycles through four Yoga layouts while keeping one retained tree alive:
   horizontal, vertical, centered, and three-column. The overlay controls
   exercise absolute positioning, visibility, resize handling, and keyboard
   updates independently of the selected flex layout. *)

module O = Opentui_core
module S = O.Lib.Styled_text
module Util = Opentui_examples_lib.Util
module Box = O.Renderables.Box
module Text = O.Renderables.Text
module Key = O.Lib.Key_decoder
module Handler = O.Lib.Key_handler

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> invalid_arg (O.Error.message error)

let ignore_ok result = ignore (expect_ok result)
let color = Util.color_of_hex

let add_child children renderable = ignore_ok (O.Layout_children.add children renderable)
let add_box_child children box = add_child children (Box.as_renderable box)

let set_width renderable value = ignore_ok (O.Renderable.set_width renderable value)
let set_height renderable value = ignore_ok (O.Renderable.set_height renderable value)

let set_flex_basis renderable value =
  ignore_ok (O.Renderable.set_flex_basis renderable value)

let set_flex_grow renderable value =
  ignore_ok (O.Renderable.set_flex_grow renderable (Some value))

let set_flex_shrink renderable value =
  ignore_ok (O.Renderable.set_flex_shrink renderable (Some value))

let set_flex_direction renderable direction =
  ignore_ok (O.Renderable.set_flex_direction renderable direction)

let set_align_items renderable align =
  ignore_ok (O.Renderable.set_align_items renderable align)

let set_justify_content renderable justify =
  ignore_ok (O.Renderable.set_justify_content renderable justify)

let set_min_width renderable value =
  ignore_ok (O.Renderable.set_min_width renderable value)

let set_min_height renderable value =
  ignore_ok (O.Renderable.set_min_height renderable value)

let set_max_width renderable value =
  ignore_ok (O.Renderable.set_max_width renderable value)

let set_position renderable ~edge value =
  ignore_ok (O.Renderable.set_position renderable ~edge value)

let set_z_index renderable value =
  ignore_ok (O.Renderable.set_z_index renderable value)

let set_position_absolute renderable ~left ~top ~z_index =
  ignore_ok
    (O.Renderable.set_position_type renderable O.Yoga.Position_absolute);
  set_position renderable ~edge:O.Yoga.Left (O.Yoga.Point left);
  set_position renderable ~edge:O.Yoga.Top (O.Yoga.Point top);
  ignore_ok (O.Renderable.set_z_index renderable z_index)

let set_position_absolute_bottom_right renderable ~right ~bottom ~z_index =
  ignore_ok
    (O.Renderable.set_position_type renderable O.Yoga.Position_absolute);
  set_position renderable ~edge:O.Yoga.Right (O.Yoga.Point right);
  set_position renderable ~edge:O.Yoga.Bottom (O.Yoga.Point bottom);
  ignore_ok (O.Renderable.set_z_index renderable z_index)

let styled_text context ?id ~foreground content =
  expect_ok
    (Text.create context ?id
       ~content:(S.create [ S.chunk ~fg:foreground content ]) ())

let set_text text ~foreground content =
  ignore_ok
    (Text.set_content text (S.create [ S.chunk ~fg:foreground content ]))

let set_box_background box background =
  ignore_ok (Box.set_background_color box background)

let set_box_visible box visible = ignore_ok (Box.set_visible box visible)

let set_box_layout renderable ~width ~height =
  set_width renderable width;
  set_height renderable height

let reset_element_layout renderable =
  set_flex_basis renderable O.Yoga.Auto;
  set_flex_grow renderable 0.0;
  set_flex_shrink renderable 0.0;
  set_width renderable O.Yoga.Auto;
  set_height renderable O.Yoga.Auto;
  ignore_ok (O.Renderable.set_min_width renderable O.Yoga.Undefined);
  ignore_ok (O.Renderable.set_max_width renderable O.Yoga.Undefined);
  ignore_ok (O.Renderable.set_min_height renderable O.Yoga.Undefined);
  ignore_ok (O.Renderable.set_max_height renderable O.Yoga.Undefined)

type layout_kind = Horizontal | Vertical | Centered | Three_column

let layout_count = 4

let layout_kind_of_index = function
  | 0 -> Horizontal
  | 1 -> Vertical
  | 2 -> Centered
  | _ -> Three_column

let layout_name = function
  | Horizontal -> "Horizontal Layout"
  | Vertical -> "Vertical Layout"
  | Centered -> "Centered Layout"
  | Three_column -> "Three Column"

type demo = {
  renderer : O.Renderer.t;
  header : Box.t;
  header_text : Text.t;
  content_area : Box.t;
  sidebar : Box.t;
  sidebar_text : Text.t;
  main_content : Box.t;
  main_content_text : Text.t;
  right_sidebar : Box.t;
  right_sidebar_text : Text.t;
  footer : Box.t;
  footer_text : Text.t;
  moveable_element : Box.t;
  absolute_positioned_box : Box.t;
  mutable current_demo_index : int;
  mutable autoplay_enabled : bool;
  mutable moveable_element_visible : bool;
  mutable moveable_element_x : int;
  mutable moveable_element_y : int;
  mutable auto_elapsed : float;
  mutable live_lease : O.Renderer.live_lease option;
  mutable pre_render : O.Renderer.pre_render_driver option;
  mutable key_subscription : O.Event_subscription.t option;
  mutable resize_subscription : O.Event_subscription.t option;
  mutable destroyed : bool;
}

let terminal_width demo =
  Int32.to_int (expect_ok (O.Renderer.terminal_width demo.renderer))

let terminal_height demo =
  Int32.to_int (expect_ok (O.Renderer.terminal_height demo.renderer))

let setup_horizontal_layout demo =
  let sidebar = Box.as_renderable demo.sidebar in
  let main_content = Box.as_renderable demo.main_content in
  set_box_visible demo.sidebar true;
  set_box_visible demo.main_content true;
  set_box_visible demo.right_sidebar false;
  reset_element_layout sidebar;
  reset_element_layout main_content;
  set_flex_direction (Box.as_renderable demo.content_area) O.Yoga.Flex_row;
  set_align_items (Box.as_renderable demo.content_area) O.Yoga.Align_stretch;
  let sidebar_width =
    Int.max 15 (int_of_float (Float.floor (float_of_int (terminal_width demo) *. 0.2)))
  in
  let sidebar_width_value = O.Yoga.Point (float_of_int sidebar_width) in
  set_flex_basis sidebar sidebar_width_value;
  set_flex_grow sidebar 0.0;
  set_flex_shrink sidebar 0.0;
  set_width sidebar sidebar_width_value;
  set_min_width sidebar (O.Yoga.Point 15.0);
  set_height sidebar O.Yoga.Auto;
  set_text demo.sidebar_text ~foreground:O.Color.white "LEFT SIDEBAR";
  set_box_background demo.sidebar (color "#64748b");
  set_flex_basis main_content O.Yoga.Auto;
  set_flex_grow main_content 1.0;
  set_flex_shrink main_content 1.0;
  set_width main_content O.Yoga.Auto;
  set_min_width main_content (O.Yoga.Point 20.0);
  set_height main_content O.Yoga.Auto;
  set_text demo.main_content_text ~foreground:(color "#1e293b") "MAIN CONTENT";
  set_box_background demo.main_content (color "#eab308")

let setup_vertical_layout demo =
  let sidebar = Box.as_renderable demo.sidebar in
  let main_content = Box.as_renderable demo.main_content in
  set_box_visible demo.sidebar true;
  set_box_visible demo.main_content true;
  set_box_visible demo.right_sidebar false;
  reset_element_layout sidebar;
  reset_element_layout main_content;
  set_flex_direction (Box.as_renderable demo.content_area) O.Yoga.Flex_column;
  set_align_items (Box.as_renderable demo.content_area) O.Yoga.Align_stretch;
  let content_height = terminal_height demo - 6 in
  let top_bar_height =
    Int.max 3 (int_of_float (Float.floor (float_of_int content_height *. 0.2)))
  in
  let top_bar_height_value = O.Yoga.Point (float_of_int top_bar_height) in
  set_flex_basis sidebar top_bar_height_value;
  set_flex_grow sidebar 0.0;
  set_flex_shrink sidebar 0.0;
  set_height sidebar top_bar_height_value;
  set_min_height sidebar (O.Yoga.Point 3.0);
  set_width sidebar O.Yoga.Auto;
  set_text demo.sidebar_text ~foreground:O.Color.white "TOP BAR";
  set_box_background demo.sidebar (color "#059669");
  set_flex_basis main_content O.Yoga.Auto;
  set_flex_grow main_content 1.0;
  set_flex_shrink main_content 1.0;
  set_height main_content O.Yoga.Auto;
  set_min_height main_content (O.Yoga.Point 5.0);
  set_width main_content O.Yoga.Auto;
  set_text demo.main_content_text ~foreground:(color "#1e293b") "MAIN CONTENT";
  set_box_background demo.main_content (color "#eab308")

let setup_centered_layout demo =
  let main_content = Box.as_renderable demo.main_content in
  set_box_visible demo.sidebar false;
  set_box_visible demo.main_content true;
  set_box_visible demo.right_sidebar false;
  reset_element_layout main_content;
  let content_area = Box.as_renderable demo.content_area in
  set_flex_direction content_area O.Yoga.Flex_row;
  set_align_items content_area O.Yoga.Align_stretch;
  set_justify_content content_area O.Yoga.Justify_center;
  let terminal_width = terminal_width demo in
  let center_width =
    Int.max 30 (int_of_float (Float.floor (float_of_int terminal_width *. 0.6)))
  in
  let center_width_value = O.Yoga.Point (float_of_int center_width) in
  set_flex_basis main_content center_width_value;
  set_flex_grow main_content 0.0;
  set_flex_shrink main_content 0.0;
  set_width main_content center_width_value;
  set_min_width main_content (O.Yoga.Point 30.0);
  set_max_width main_content
    (O.Yoga.Point
       (float_of_int
          (int_of_float (Float.floor (float_of_int terminal_width *. 0.8)))));
  set_height main_content O.Yoga.Auto;
  set_text demo.main_content_text ~foreground:(color "#1e293b")
    "CENTERED CONTENT";
  set_box_background demo.main_content (color "#7c3aed")

let setup_three_column_layout demo =
  let sidebar = Box.as_renderable demo.sidebar in
  let main_content = Box.as_renderable demo.main_content in
  let right_sidebar = Box.as_renderable demo.right_sidebar in
  set_box_visible demo.sidebar true;
  set_box_visible demo.main_content true;
  set_box_visible demo.right_sidebar true;
  reset_element_layout sidebar;
  reset_element_layout main_content;
  reset_element_layout right_sidebar;
  let content_area = Box.as_renderable demo.content_area in
  set_flex_direction content_area O.Yoga.Flex_row;
  set_align_items content_area O.Yoga.Align_stretch;
  let sidebar_width =
    Int.max 12 (int_of_float (Float.floor (float_of_int (terminal_width demo) *. 0.15)))
  in
  let sidebar_width_value = O.Yoga.Point (float_of_int sidebar_width) in
  set_flex_basis sidebar sidebar_width_value;
  set_flex_grow sidebar 0.0;
  set_flex_shrink sidebar 0.0;
  set_width sidebar sidebar_width_value;
  set_min_width sidebar (O.Yoga.Point 12.0);
  set_height sidebar O.Yoga.Auto;
  set_text demo.sidebar_text ~foreground:O.Color.white "LEFT";
  set_box_background demo.sidebar (color "#dc2626");
  set_flex_basis main_content O.Yoga.Auto;
  set_flex_grow main_content 1.0;
  set_flex_shrink main_content 1.0;
  set_width main_content O.Yoga.Auto;
  set_min_width main_content (O.Yoga.Point 20.0);
  set_height main_content O.Yoga.Auto;
  set_text demo.main_content_text ~foreground:(color "#1e293b") "CENTER";
  set_box_background demo.main_content (color "#059669");
  set_flex_basis right_sidebar sidebar_width_value;
  set_flex_grow right_sidebar 0.0;
  set_flex_shrink right_sidebar 0.0;
  set_width right_sidebar sidebar_width_value;
  set_min_width right_sidebar (O.Yoga.Point 12.0);
  set_height right_sidebar O.Yoga.Auto;
  set_text demo.right_sidebar_text ~foreground:O.Color.white "RIGHT";
  set_box_background demo.right_sidebar (color "#7c3aed")

let apply_layout demo layout =
  match layout with
  | Horizontal -> setup_horizontal_layout demo
  | Vertical -> setup_vertical_layout demo
  | Centered -> setup_centered_layout demo
  | Three_column -> setup_three_column_layout demo

let update_footer_text demo =
  let autoplay_status = if demo.autoplay_enabled then "ON" else "OFF" in
  let moveable_status = if demo.moveable_element_visible then "ON" else "OFF" in
  set_text demo.footer_text ~foreground:O.Color.white
    (Printf.sprintf
       "SPACE: next | R: restart | P: autoplay (%s) | V: overlay (%s) | WASD: move"
       autoplay_status moveable_status)

let apply_current_demo demo =
  let layout = layout_kind_of_index demo.current_demo_index in
  let autoplay_status = if demo.autoplay_enabled then "AUTO" else "MANUAL" in
  set_text demo.header_text ~foreground:O.Color.white
    (Printf.sprintf "%s (%d/%d) - %s" (layout_name layout)
       (demo.current_demo_index + 1) layout_count autoplay_status);
  apply_layout demo layout;
  demo.auto_elapsed <- 0.0

let next_demo demo =
  demo.current_demo_index <- (demo.current_demo_index + 1) mod layout_count;
  apply_current_demo demo

let release_live demo =
  Option.iter O.Renderer.release_live_lease demo.live_lease;
  demo.live_lease <- None

let start_live demo =
  match demo.live_lease with
  | Some _ -> ()
  | None -> demo.live_lease <- Some (expect_ok (O.Renderer.acquire_live_lease demo.renderer))

let toggle_autoplay demo =
  demo.autoplay_enabled <- not demo.autoplay_enabled;
  if demo.autoplay_enabled then begin
    demo.auto_elapsed <- 0.0;
    start_live demo
  end
  else release_live demo;
  update_footer_text demo

let toggle_moveable_element demo =
  demo.moveable_element_visible <- not demo.moveable_element_visible;
  set_box_visible demo.moveable_element demo.moveable_element_visible;
  update_footer_text demo

let set_moveable_position demo ~left ~top =
  let renderable = Box.as_renderable demo.moveable_element in
  set_position renderable ~edge:O.Yoga.Left (O.Yoga.Point (float_of_int left));
  set_position renderable ~edge:O.Yoga.Top (O.Yoga.Point (float_of_int top))

let move_moveable_element demo delta_x delta_y =
  let width = terminal_width demo in
  let height = terminal_height demo in
  demo.moveable_element_x <- demo.moveable_element_x + delta_x;
  demo.moveable_element_y <- demo.moveable_element_y + delta_y;
  demo.moveable_element_x <-
    Int.max 0 (Int.min (width - 8) demo.moveable_element_x);
  demo.moveable_element_y <-
    Int.max 0 (Int.min (height - 3) demo.moveable_element_y);
  set_moveable_position demo ~left:demo.moveable_element_x
    ~top:demo.moveable_element_y

let center_moveable_element demo =
  let width = terminal_width demo in
  let height = terminal_height demo in
  demo.moveable_element_x <-
    int_of_float (Float.floor ((float_of_int width -. 8.0) /. 2.0));
  demo.moveable_element_y <-
    int_of_float (Float.floor ((float_of_int height -. 3.0) /. 2.0));
  set_moveable_position demo ~left:demo.moveable_element_x
    ~top:demo.moveable_element_y

let handle_key demo key_event =
  if not demo.destroyed then
    match Handler.key_event_kind key_event with
    | Handler.Keyrelease | Handler.Paste -> ()
    | Handler.Keypress -> (
        match Handler.key key_event with
        | Key.Named Key.Space -> next_demo demo
        | Key.Character bytes -> (
            match String.lowercase_ascii (Bytes.to_string bytes) with
            | "r" ->
                demo.current_demo_index <- 0;
                apply_current_demo demo
            | "p" -> toggle_autoplay demo
            | "v" -> toggle_moveable_element demo
            | "w" -> move_moveable_element demo 0 (-1)
            | "a" -> move_moveable_element demo (-1) 0
            | "s" -> move_moveable_element demo 0 1
            | "d" -> move_moveable_element demo 1 0
            | _ -> ())
        | Key.Named _ -> ())

let update_autoplay demo delta_seconds =
  if demo.autoplay_enabled then begin
    demo.auto_elapsed <- demo.auto_elapsed +. delta_seconds;
    if Float.compare demo.auto_elapsed 4.0 >= 0 then next_demo demo
  end

let create_demo renderer =
  let context = O.Renderer.context renderer in
  ignore_ok (O.Renderer.set_background_color renderer ~color:(color "#001122"));
  let header =
    expect_ok
      (Box.create context ~id:"header" ~background_color:(color "#3b82f6")
         ~border_style:O.Lib.Border.Single ~border:Box.all_borders ())
  in
  let header_renderable = Box.as_renderable header in
  set_width header_renderable O.Yoga.Auto;
  set_height header_renderable (O.Yoga.Point 3.0);
  set_flex_shrink header_renderable 0.0;
  set_align_items header_renderable O.Yoga.Align_center;
  let header_text =
    styled_text context ~id:"header-text" ~foreground:O.Color.white "LAYOUT DEMO"
  in
  set_z_index (Text.as_renderable header_text) 1;
  add_child (Box.children header) (Text.as_renderable header_text);

  let content_area =
    expect_ok (Box.create context ~id:"content-area" ~should_fill:false ())
  in
  let content_area_renderable = Box.as_renderable content_area in
  set_width content_area_renderable O.Yoga.Auto;
  set_height content_area_renderable O.Yoga.Auto;
  set_flex_direction content_area_renderable O.Yoga.Flex_row;
  set_flex_grow content_area_renderable 1.0;
  set_flex_shrink content_area_renderable 1.0;

  let sidebar =
    expect_ok
      (Box.create context ~id:"sidebar" ~background_color:(color "#64748b")
         ~border_style:O.Lib.Border.Single ~border:Box.all_borders ())
  in
  let sidebar_renderable = Box.as_renderable sidebar in
  set_width sidebar_renderable O.Yoga.Auto;
  set_height sidebar_renderable O.Yoga.Auto;
  set_flex_grow sidebar_renderable 0.0;
  set_flex_shrink sidebar_renderable 0.0;
  set_flex_direction sidebar_renderable O.Yoga.Flex_row;
  set_align_items sidebar_renderable O.Yoga.Align_center;
  set_justify_content sidebar_renderable O.Yoga.Justify_center;
  let sidebar_text =
    styled_text context ~id:"sidebar-text" ~foreground:O.Color.white "SIDEBAR"
  in
  set_z_index (Text.as_renderable sidebar_text) 1;
  add_child (Box.children sidebar) (Text.as_renderable sidebar_text);

  let main_content =
    expect_ok
      (Box.create context ~id:"main-content"
         ~background_color:(color "#919599")
         ~border_style:O.Lib.Border.Single ~border:Box.all_borders ())
  in
  let main_content_renderable = Box.as_renderable main_content in
  set_width main_content_renderable O.Yoga.Auto;
  set_height main_content_renderable O.Yoga.Auto;
  set_flex_grow main_content_renderable 1.0;
  set_flex_shrink main_content_renderable 1.0;
  set_flex_direction main_content_renderable O.Yoga.Flex_row;
  set_align_items main_content_renderable O.Yoga.Align_center;
  set_justify_content main_content_renderable O.Yoga.Justify_center;
  let main_content_text =
    styled_text context ~id:"main-content-text" ~foreground:(color "#1e293b")
      "MAIN CONTENT"
  in
  set_z_index (Text.as_renderable main_content_text) 1;
  add_child (Box.children main_content) (Text.as_renderable main_content_text);

  let right_sidebar =
    expect_ok
      (Box.create context ~id:"right-sidebar"
         ~background_color:(color "#7c3aed")
         ~border_style:O.Lib.Border.Single ~border:Box.all_borders ())
  in
  let right_sidebar_renderable = Box.as_renderable right_sidebar in
  set_width right_sidebar_renderable O.Yoga.Auto;
  set_height right_sidebar_renderable O.Yoga.Auto;
  set_flex_grow right_sidebar_renderable 0.0;
  set_flex_shrink right_sidebar_renderable 0.0;
  set_flex_direction right_sidebar_renderable O.Yoga.Flex_row;
  set_align_items right_sidebar_renderable O.Yoga.Align_center;
  set_justify_content right_sidebar_renderable O.Yoga.Justify_center;
  let right_sidebar_text =
    styled_text context ~id:"right-sidebar-text" ~foreground:O.Color.white "RIGHT"
  in
  set_z_index (Text.as_renderable right_sidebar_text) 1;
  add_child (Box.children right_sidebar) (Text.as_renderable right_sidebar_text);

  let footer =
    expect_ok
      (Box.create context ~id:"footer" ~background_color:(color "#1e40af")
         ~border_style:O.Lib.Border.Single ~border:Box.all_borders ())
  in
  let footer_renderable = Box.as_renderable footer in
  set_width footer_renderable O.Yoga.Auto;
  set_height footer_renderable (O.Yoga.Point 3.0);
  set_flex_shrink footer_renderable 0.0;
  set_flex_direction footer_renderable O.Yoga.Flex_row;
  set_align_items footer_renderable O.Yoga.Align_center;
  set_justify_content footer_renderable O.Yoga.Justify_center;
  let footer_text =
    styled_text context ~id:"footer-text" ~foreground:O.Color.white ""
  in
  set_z_index (Text.as_renderable footer_text) 1;
  add_child (Box.children footer) (Text.as_renderable footer_text);

  let moveable_element =
    expect_ok
      (Box.create context ~id:"moveable"
         ~background_color:(color "#ff6b6b")
         ~border_style:O.Lib.Border.Single ~border:Box.all_borders
         ~border_color:(color "#ff4757") ())
  in
  let moveable_renderable = Box.as_renderable moveable_element in
  set_position_absolute moveable_renderable ~left:0.0 ~top:0.0 ~z_index:100;
  set_box_layout moveable_renderable ~width:(O.Yoga.Point 8.0)
    ~height:(O.Yoga.Point 3.0);
  set_flex_direction moveable_renderable O.Yoga.Flex_row;
  set_align_items moveable_renderable O.Yoga.Align_center;
  set_justify_content moveable_renderable O.Yoga.Justify_center;
  let moveable_text =
    styled_text context ~id:"moveable-text" ~foreground:O.Color.white "MOVE"
  in
  set_z_index (Text.as_renderable moveable_text) 101;
  add_child (Box.children moveable_element) (Text.as_renderable moveable_text);

  let absolute_positioned_box =
    expect_ok
      (Box.create context ~id:"absolute-positioned-box"
         ~background_color:(color "#22c55e")
         ~border_style:O.Lib.Border.Single ~border:Box.all_borders
         ~border_color:(color "#16a34a") ())
  in
  let absolute_renderable = Box.as_renderable absolute_positioned_box in
  set_position_absolute_bottom_right absolute_renderable ~right:1.0 ~bottom:1.0
    ~z_index:150;
  set_box_layout absolute_renderable ~width:(O.Yoga.Point 20.0)
    ~height:(O.Yoga.Point 3.0);
  set_flex_direction absolute_renderable O.Yoga.Flex_row;
  set_align_items absolute_renderable O.Yoga.Align_center;
  set_justify_content absolute_renderable O.Yoga.Justify_center;
  let absolute_positioned_text =
    styled_text context ~id:"absolute-positioned-text" ~foreground:O.Color.white
      "BOTTOM RIGHT"
  in
  set_z_index (Text.as_renderable absolute_positioned_text) 151;
  add_child (Box.children absolute_positioned_box)
    (Text.as_renderable absolute_positioned_text);

  add_box_child (Box.children content_area) sidebar;
  add_box_child (Box.children content_area) main_content;
  add_box_child (Box.children content_area) right_sidebar;
  set_box_visible right_sidebar false;
  add_box_child (O.Renderer.children renderer) header;
  add_box_child (O.Renderer.children renderer) content_area;
  add_box_child (O.Renderer.children renderer) footer;
  add_box_child (O.Renderer.children renderer) moveable_element;
  add_box_child (O.Renderer.children renderer) absolute_positioned_box;
  let demo =
    {
      renderer;
      header;
      header_text;
      content_area;
      sidebar;
      sidebar_text;
      main_content;
      main_content_text;
      right_sidebar;
      right_sidebar_text;
      footer;
      footer_text;
      moveable_element;
      absolute_positioned_box;
      current_demo_index = 0;
      autoplay_enabled = true;
      moveable_element_visible = true;
      moveable_element_x = 0;
      moveable_element_y = 0;
      auto_elapsed = 0.0;
      live_lease = None;
      pre_render = None;
      key_subscription = None;
      resize_subscription = None;
      destroyed = false;
    }
  in
  let pre_render =
    expect_ok
      (O.Renderer.attach_pre_render renderer (fun delta_seconds ->
           if not demo.destroyed then update_autoplay demo delta_seconds))
  in
  demo.pre_render <- Some pre_render;
  let key_subscription =
    expect_ok (O.Renderer.on_keypress renderer (handle_key demo))
  in
  demo.key_subscription <- Some key_subscription;
  let resize_subscription =
    expect_ok
      (O.Renderer.on_resize renderer (fun _resize_event ->
           if not demo.destroyed then center_moveable_element demo))
  in
  demo.resize_subscription <- Some resize_subscription;
  center_moveable_element demo;
  apply_current_demo demo;
  update_footer_text demo;
  start_live demo;
  demo

let remove_box_child children box = ignore_ok (O.Layout_children.remove children (Box.as_renderable box))

let destroy demo =
  if not demo.destroyed then begin
    demo.destroyed <- true;
    Option.iter O.Event_subscription.cancel demo.key_subscription;
    Option.iter O.Event_subscription.cancel demo.resize_subscription;
    Option.iter O.Renderer.detach_pre_render demo.pre_render;
    release_live demo;
    remove_box_child (O.Renderer.children demo.renderer) demo.header;
    remove_box_child (O.Renderer.children demo.renderer) demo.content_area;
    remove_box_child (O.Renderer.children demo.renderer) demo.footer;
    remove_box_child (O.Renderer.children demo.renderer) demo.moveable_element;
    remove_box_child (O.Renderer.children demo.renderer)
      demo.absolute_positioned_box;
    Box.destroy_recursively demo.header;
    Box.destroy_recursively demo.content_area;
    Box.destroy_recursively demo.footer;
    Box.destroy_recursively demo.moveable_element;
    Box.destroy_recursively demo.absolute_positioned_box;
    demo.key_subscription <- None;
    demo.resize_subscription <- None;
    demo.pre_render <- None;
    demo.live_lease <- None
  end

let run renderer ~exit ~copy_to_clipboard =
  ignore copy_to_clipboard;
  let demo = create_demo renderer in
  ignore_ok (O.Renderer.attach_before_destroy renderer (fun () -> destroy demo));
  Opentui_examples_lib.Standalone_keys.setup_common_demo_keys renderer
    ~on_ctrl_c:exit

let () =
  Eio_main.run @@ fun env ->
  Opentui_examples_lib.App.run env ~target_frames_per_second:30
    ~init:(fun ~exit ~copy_to_clipboard renderer ->
      run renderer ~exit ~copy_to_clipboard)
