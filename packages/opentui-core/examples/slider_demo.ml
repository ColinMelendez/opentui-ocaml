(* Port of vendor/opentui/packages/examples/src/slider-demo.ts.

   The demo keeps the reference's layout and seven slider configurations while
   using the local retained Slider, Box, and Text APIs. *)

module O = Opentui_core
module S = O.Lib.Styled_text
module Box = O.Renderables.Box
module Slider = O.Renderables.Slider
module Text = O.Renderables.Text
module Key = O.Lib.Key_decoder
module Handler = O.Lib.Key_handler
module Util = Opentui_examples_lib.Util

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> invalid_arg (O.Error.message error)

let ignore_ok result = ignore (expect_ok result)
let color = Util.color_of_hex

let add_child children renderable =
  ignore_ok (O.Layout_children.add children renderable)

let add_box_child children box = add_child children (Box.as_renderable box)
let add_text_child children text = add_child children (Text.as_renderable text)

let set_width renderable value = ignore_ok (O.Renderable.set_width renderable value)
let set_height renderable value = ignore_ok (O.Renderable.set_height renderable value)

let set_flex_grow renderable value =
  ignore_ok (O.Renderable.set_flex_grow renderable (Some value))

let set_flex_direction renderable value =
  ignore_ok (O.Renderable.set_flex_direction renderable value)

let set_align_items renderable value =
  ignore_ok (O.Renderable.set_align_items renderable value)

let set_padding_all renderable value =
  ignore_ok
    (O.Renderable.set_padding renderable ~edge:O.Yoga.All
       (O.Yoga.Point value))

let set_margin_bottom renderable value =
  ignore_ok
    (O.Renderable.set_margin renderable ~edge:O.Yoga.Bottom
       (O.Yoga.Point value))

let set_margin_right renderable value =
  ignore_ok
    (O.Renderable.set_margin renderable ~edge:O.Yoga.Right
       (O.Yoga.Point value))

let set_max_width renderable value =
  ignore_ok (O.Renderable.set_max_width renderable (O.Yoga.Percent value))

let set_max_height renderable value =
  ignore_ok (O.Renderable.set_max_height renderable (O.Yoga.Percent value))

let styled_text context ?id ?width ~content () =
  let text = expect_ok (Text.create context ?id ~content ()) in
  Option.iter (fun value -> set_width (Text.as_renderable text) value) width;
  text

let bold_foreground foreground text =
  S.chunk ~fg:foreground ~attributes:O.Lib.Text_attributes.bold text

let gray_text text = S.fg (color "#565f89") (S.Text text)

let slider_label ~label_color ~name ~description =
  S.create
    [ bold_foreground label_color name; S.chunk " "; gray_text description ]

let vertical_slider_label ~label_color ~name ~description =
  S.create
    [
      bold_foreground label_color name;
      S.chunk "\n";
      gray_text description;
    ]

let format_value precision value =
  if Int.equal precision 1 then Printf.sprintf "%.1f" value
  else Printf.sprintf "%.2f" value

let horizontal_value_content ~label_color ~precision value =
  S.create
    [
      bold_foreground label_color "Value:";
      S.chunk (" " ^ format_value precision value);
    ]

let vertical_value_content ~label_color ~precision value =
  S.create [ bold_foreground label_color (format_value precision value) ]

type slider_view = {
  slider : Slider.t;
  value_text : Text.t;
  label_color : O.Color.t;
  precision : int;
  vertical : bool;
}

type demo = {
  renderer : O.Renderer.t;
  main_container : Box.t;
  views : slider_view array;
  mutable animation_time_ms : float;
  change_subscriptions : O.Event_subscription.t list;
  mutable key_subscription : O.Event_subscription.t option;
  mutable pre_render : O.Renderer.pre_render_driver option;
  mutable live_lease : O.Renderer.live_lease option;
  mutable destroyed : bool;
}

let update_view view =
  let content =
    if view.vertical then
      vertical_value_content ~label_color:view.label_color
        ~precision:view.precision (Slider.value view.slider)
    else
      horizontal_value_content ~label_color:view.label_color
        ~precision:view.precision (Slider.value view.slider)
  in
  ignore_ok (Text.set_content view.value_text content)

let update_displays demo = Array.iter update_view demo.views

let set_slider_value view value = ignore_ok (Slider.set_value view.slider value)

let reset_sliders demo =
  let defaults = [| 25.0; 100.0; 25.0; 0.0; 0.0; 50.0; 50.0 |] in
  Array.iteri
    (fun index view -> set_slider_value view defaults.(index))
    demo.views;
  update_displays demo

let focus_slider demo index =
  Array.iter
    (fun view -> ignore_ok (O.Renderable.blur (Slider.as_renderable view.slider)))
    demo.views;
  if Int.compare index 1 >= 0 && Int.compare index (Array.length demo.views) <= 0 then
    let view = demo.views.(index - 1) in
    ignore_ok (O.Renderable.focus (Slider.as_renderable view.slider))

let handle_key demo key_event =
  if Handler.key_event_kind key_event = Handler.Keypress then begin
    let modifiers = Handler.key_modifiers key_event in
    if not modifiers.ctrl && not modifiers.meta then
      match Handler.key key_event with
      | Key.Character bytes -> (
          match String.lowercase_ascii (Bytes.to_string bytes) with
          | "r" -> reset_sliders demo
          | "1" -> focus_slider demo 1
          | "2" -> focus_slider demo 2
          | "3" -> focus_slider demo 3
          | "4" -> focus_slider demo 4
          | "5" -> focus_slider demo 5
          | "6" -> focus_slider demo 6
          | "7" -> focus_slider demo 7
          | _ -> ())
      | Key.Named _ -> ()
  end

let clamp value minimum maximum =
  Float.max minimum (Float.min maximum value)

let update_animation demo delta_seconds =
  demo.animation_time_ms <- demo.animation_time_ms +. (delta_seconds *. 1000.0);
  let horizontal_value =
    25.0 +. (Float.sin (demo.animation_time_ms *. 0.002) *. 25.0)
  in
  let vertical_value =
    50.0 +. (Float.cos (demo.animation_time_ms *. 0.0015) *. 50.0)
  in
  set_slider_value demo.views.(2) (clamp horizontal_value 0.0 50.0);
  set_slider_value demo.views.(6) (clamp vertical_value 0.0 100.0)

let create_slider context ~orientation ?id ?viewport_size ?(value = 0.0)
    ?(minimum = 0.0) ?(maximum = 100.0) ?width ?height ~background_color
    ~foreground_color () =
  expect_ok
    (Slider.create context ~orientation ?id ?viewport_size ~value ~min:minimum
       ~max:maximum ~background_color ~foreground_color ~focusable:true ?width
       ?height ())

let make_horizontal_section context ~id ~label_color ~name ~description
    ~value ~minimum ~maximum ?viewport_size ?width ~height ~precision
    ~background_color ~foreground_color parent =
  let section =
    expect_ok
      (Box.create context ~id ~background_color
         ~should_fill:true ())
  in
  let section_node = Box.as_renderable section in
  set_width section_node (O.Yoga.Percent 100.0);
  set_flex_direction section_node O.Yoga.Flex_column;
  set_margin_bottom section_node 1.0;
  set_padding_all section_node 1.0;
  let label =
    styled_text context
      ~content:(slider_label ~label_color ~name ~description) ()
  in
  let value_text =
    styled_text context
      ~content:(horizontal_value_content ~label_color ~precision value) ()
  in
  let slider =
    create_slider context ~orientation:Slider.Horizontal ~id:(id ^ "-control")
      ?viewport_size ~value ~minimum ~maximum ?width ~height
      ~background_color:(color "#414868") ~foreground_color ()
  in
  add_text_child (Box.children section) label;
  add_text_child (Box.children section) value_text;
  add_child (Box.children section) (Slider.as_renderable slider);
  add_box_child (Box.children parent) section;
  { slider; value_text; label_color; precision; vertical = false }

let make_vertical_section context ~id ~label_color ~name ~description
    ~container_width ~slider_width ~value ~minimum ~maximum ~viewport_size
    ?slider_height ~precision ~background_color ~foreground_color parent =
  let section =
    expect_ok
      (Box.create context ~id ~background_color
         ~should_fill:true ())
  in
  let section_node = Box.as_renderable section in
  set_width section_node (O.Yoga.Point container_width);
  set_height section_node (O.Yoga.Percent 100.0);
  set_flex_direction section_node O.Yoga.Flex_column;
  set_align_items section_node O.Yoga.Align_flex_end;
  set_margin_right section_node 1.0;
  set_padding_all section_node 1.0;
  let wrapper =
    expect_ok (Box.create context ~id:(id ^ "-wrapper") ~should_fill:false ())
  in
  let wrapper_node = Box.as_renderable wrapper in
  set_flex_direction wrapper_node O.Yoga.Flex_row;
  set_height wrapper_node (O.Yoga.Percent 100.0);
  set_flex_grow wrapper_node 1.0;
  let label =
    styled_text context ~width:(O.Yoga.Point 3.0)
      ~content:(vertical_slider_label ~label_color ~name ~description) ()
  in
  let slider =
    create_slider context ~orientation:Slider.Vertical ~id:(id ^ "-control")
      ~viewport_size ~value ~minimum ~maximum
      ~width:(O.Yoga.Point slider_width) ?height:slider_height
      ~background_color:(color "#414868") ~foreground_color ()
  in
  let value_text =
    styled_text context
      ~content:(vertical_value_content ~label_color ~precision value) ()
  in
  add_text_child (Box.children wrapper) label;
  add_child (Box.children wrapper) (Slider.as_renderable slider);
  add_box_child (Box.children section) wrapper;
  add_text_child (Box.children section) value_text;
  add_box_child (Box.children parent) section;
  { slider; value_text; label_color; precision; vertical = true }

let create_visuals renderer =
  let context = O.Renderer.context renderer in
  let main_container =
    expect_ok
      (Box.create context ~id:"slider-demo-main-container"
         ~background_color:(color "#1a1b26") ~should_fill:true ())
  in
  let main_node = Box.as_renderable main_container in
  set_flex_grow main_node 1.0;
  set_max_height main_node 100.0;
  set_max_width main_node 100.0;
  set_flex_direction main_node O.Yoga.Flex_column;

  let sliders_container =
    expect_ok
      (Box.create context ~id:"sliders-container"
         ~background_color:(color "#1a1b26") ~should_fill:true ())
  in
  let sliders_node = Box.as_renderable sliders_container in
  set_width sliders_node (O.Yoga.Percent 100.0);
  set_flex_grow sliders_node 1.0;
  set_flex_direction sliders_node O.Yoga.Flex_column;
  set_padding_all sliders_node 2.0;

  let h1 =
    make_horizontal_section context ~id:"h1-container"
      ~label_color:(color "#e0af68") ~name:"H1"
      ~description:"- 1h×100w (0-50)" ~value:25.0 ~minimum:0.0
      ~maximum:50.0 ~viewport_size:1.0 ~width:(O.Yoga.Percent 100.0)
      ~height:(O.Yoga.Point 1.0) ~precision:1
      ~background_color:(color "#24283b")
      ~foreground_color:(color "#e0af68") sliders_container
  in
  let h2 =
    make_horizontal_section context ~id:"h2-container"
      ~label_color:(color "#bb9af7") ~name:"H2"
      ~description:"- 5h×100w (0-200)" ~value:100.0 ~minimum:0.0
      ~maximum:200.0 ~viewport_size:50.0 ~width:(O.Yoga.Percent 100.0)
      ~height:(O.Yoga.Point 5.0) ~precision:1
      ~background_color:(color "#24283b")
      ~foreground_color:(color "#bb9af7") sliders_container
  in
  let h3 =
    make_horizontal_section context ~id:"h3-container"
      ~label_color:(color "#FF6B6B") ~name:"H3"
      ~description:"- 1h×80w (animated, sub-cell rendering)" ~value:25.0
      ~minimum:0.0 ~maximum:50.0 ~viewport_size:0.1
      ~height:(O.Yoga.Point 1.0) ~precision:2
      ~background_color:(color "#24283b")
      ~foreground_color:(color "#FF6B6B") sliders_container
  in

  let vertical_container =
    expect_ok
      (Box.create context ~id:"vertical-container"
         ~background_color:(color "#1a1b26") ~should_fill:true ())
  in
  let vertical_node = Box.as_renderable vertical_container in
  set_width vertical_node (O.Yoga.Percent 100.0);
  set_height vertical_node (O.Yoga.Point 17.0);
  set_flex_direction vertical_node O.Yoga.Flex_row;
  set_margin_bottom vertical_node 1.0;
  set_padding_all vertical_node 1.0;

  let v1 =
    make_vertical_section context ~id:"v1-container"
      ~label_color:(color "#f7768e") ~name:"V1" ~description:"1w"
      ~container_width:8.0 ~slider_width:1.0 ~value:0.0 ~minimum:(-10.0)
      ~maximum:10.0 ~viewport_size:1.0 ~precision:1
      ~background_color:(color "#24283b")
      ~foreground_color:(color "#f7768e") vertical_container
  in
  let v2 =
    make_vertical_section context ~id:"v2-container"
      ~label_color:(color "#ff9e64") ~name:"V2" ~description:"3w"
      ~container_width:10.0 ~slider_width:3.0 ~value:0.0 ~minimum:(-50.0)
      ~maximum:50.0 ~viewport_size:5.0 ~precision:1
      ~background_color:(color "#24283b")
      ~foreground_color:(color "#ff9e64") vertical_container
  in
  let v3 =
    make_vertical_section context ~id:"v3-container"
      ~label_color:(color "#73daca") ~name:"V3" ~description:"5w"
      ~container_width:12.0 ~slider_width:5.0 ~value:50.0 ~minimum:0.0
      ~maximum:100.0 ~viewport_size:10.0 ~precision:1
      ~background_color:(color "#24283b")
      ~foreground_color:(color "#73daca") vertical_container
  in
  let va =
    make_vertical_section context ~id:"animated-v-container"
      ~label_color:(color "#FF6B6B") ~name:"VA" ~description:"2w"
      ~container_width:10.0 ~slider_width:2.0 ~value:50.0 ~minimum:0.0
      ~maximum:100.0 ~viewport_size:0.2 ~slider_height:(O.Yoga.Point 10.0)
      ~precision:2 ~background_color:(color "#24283b")
      ~foreground_color:(color "#FF6B6B") vertical_container
  in
  add_box_child (Box.children sliders_container) vertical_container;
  let spacer =
    expect_ok (Box.create context ~id:"spacer" ~should_fill:false ())
  in
  let spacer_node = Box.as_renderable spacer in
  set_width spacer_node (O.Yoga.Percent 100.0);
  set_flex_grow spacer_node 1.0;
  add_box_child (Box.children sliders_container) spacer;

  let instructions =
    expect_ok
      (Box.create context ~id:"instructions"
         ~background_color:(color "#2a2b3a") ~should_fill:true ())
  in
  let instructions_node = Box.as_renderable instructions in
  set_width instructions_node (O.Yoga.Percent 100.0);
  set_flex_direction instructions_node O.Yoga.Flex_column;
  ignore_ok
    (O.Renderable.set_padding instructions_node ~edge:O.Yoga.Left
       (O.Yoga.Point 1.0));
  let instructions_text1 =
    styled_text context
      ~content:
        (S.create
           [
             bold_foreground (color "#7aa2f7") "Slider Demo";
             S.chunk " ";
             gray_text "-";
             S.chunk " ";
             bold_foreground (color "#FFFF00") "Mouse";
             S.chunk " ";
             S.fg (color "#c0caf5") (S.Text "Click & drag on sliders");
             S.chunk " ";
             gray_text "|";
             S.chunk " ";
             bold_foreground (color "#FFAA00") "R";
             S.chunk " ";
             S.fg (color "#c0caf5") (S.Text "Reset all");
             S.chunk " ";
             gray_text "|";
             S.chunk " ";
             bold_foreground (color "#00FF00") "1-7";
             S.chunk " ";
             S.fg (color "#c0caf5") (S.Text "Focus sliders");
           ]) ()
  in
  let instructions_text2 =
    styled_text context
      ~content:
        (S.create
           [
             bold_foreground (color "#7aa2f7") "Features:";
             S.chunk " ";
             S.fg (color "#c0caf5")
               (S.Text
                  "Different ranges, step sizes, orientations & dimensions (1-5 height/width)");
           ]) ()
  in
  add_text_child (Box.children instructions) instructions_text1;
  add_text_child (Box.children instructions) instructions_text2;

  add_box_child (Box.children main_container) sliders_container;
  add_box_child (Box.children main_container) instructions;
  add_box_child (O.Renderer.children renderer) main_container;
  let views = [| h1; h2; h3; v1; v2; v3; va |] in
  { renderer; main_container; views; animation_time_ms = 0.0;
    change_subscriptions = []; key_subscription = None; pre_render = None;
    live_lease = None; destroyed = false }

let install_change_handlers demo =
  let subscriptions =
    Array.to_list
      (Array.map
         (fun view ->
           Slider.on_change view.slider (fun value ->
               ignore value;
               update_displays demo))
         demo.views)
  in
  { demo with change_subscriptions = subscriptions }

let destroy demo =
  if not demo.destroyed then begin
    demo.destroyed <- true;
    Option.iter O.Event_subscription.cancel demo.key_subscription;
    List.iter O.Event_subscription.cancel demo.change_subscriptions;
    Option.iter O.Renderer.detach_pre_render demo.pre_render;
    Option.iter O.Renderer.release_live_lease demo.live_lease;
    Box.destroy_recursively demo.main_container;
    demo.key_subscription <- None;
    demo.pre_render <- None;
    demo.live_lease <- None
  end

let create_demo renderer =
  ignore_ok
    (O.Renderer.set_background_color renderer ~color:(color "#1a1b26"));
  let demo = create_visuals renderer |> install_change_handlers in
  update_displays demo;
  let live_lease = expect_ok (O.Renderer.acquire_live_lease renderer) in
  demo.live_lease <- Some live_lease;
  let pre_render =
    expect_ok
      (O.Renderer.attach_pre_render renderer (fun delta_seconds ->
           if not demo.destroyed then update_animation demo delta_seconds))
  in
  demo.pre_render <- Some pre_render;
  let key_subscription =
    expect_ok (O.Renderer.on_keypress renderer (handle_key demo))
  in
  demo.key_subscription <- Some key_subscription;
  ignore_ok
    (O.Renderer.attach_before_destroy renderer (fun () -> destroy demo));
  demo

let run renderer ~exit ~copy_to_clipboard =
  ignore copy_to_clipboard;
  let demo = create_demo renderer in
  Opentui_examples_lib.Standalone_keys.setup_common_demo_keys renderer
    ~on_ctrl_c:exit;
  ignore demo

let () =
  Eio_main.run @@ fun env ->
  Opentui_examples_lib.App.run env ~target_frames_per_second:60
    ~init:(fun ~exit ~copy_to_clipboard renderer ->
      run renderer ~exit ~copy_to_clipboard)
