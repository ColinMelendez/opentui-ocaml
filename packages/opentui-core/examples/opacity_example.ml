(* Port of vendor/opentui/packages/examples/src/opacity-example.ts.

   Demonstrates retained-renderable opacity, overlapping alpha compositing,
   nested opacity multiplication, and live animation driven by the renderer's
   pre-render hook. *)

module O = Opentui_core
module S = O.Lib.Styled_text
module Box = O.Renderables.Box
module Text = O.Renderables.Text
module Key = O.Lib.Key_decoder
module Handler = O.Lib.Key_handler
module Util = Opentui_examples_lib.Util

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> invalid_arg (O.Error.message error)

let color = Util.color_of_hex

type opacity_box = {
  box : Box.t;
  opacity_text : Text.t;
}

type demo = {
  renderer : O.Renderer.t;
  info_text : Text.t;
  boxes : opacity_box array;
  mutable phase : float;
  mutable animating : bool;
  mutable live_lease : O.Renderer.live_lease option;
  mutable pre_render : O.Renderer.pre_render_driver option;
}

let set_position renderable ~edge ~value =
  ignore (expect_ok (O.Renderable.set_position renderable ~edge value))

let set_layout renderable ~width ~height =
  ignore (expect_ok (O.Renderable.set_width renderable (O.Yoga.Point width)));
  ignore (expect_ok (O.Renderable.set_height renderable (O.Yoga.Point height)))

let set_centered_column renderable =
  ignore (expect_ok (O.Renderable.set_flex_direction renderable O.Yoga.Flex_column));
  ignore (expect_ok (O.Renderable.set_align_items renderable O.Yoga.Align_center));
  ignore (expect_ok (O.Renderable.set_justify_content renderable O.Yoga.Justify_center))

let styled_text context ?id ~foreground content =
  expect_ok
    (Text.create context ?id
       ~content:(S.create [ S.chunk ~fg:foreground content ]) ())

let add_child children renderable =
  ignore (expect_ok (O.Layout_children.add children (Text.as_renderable renderable)))

let add_box_child children box =
  ignore (expect_ok (O.Layout_children.add children (Box.as_renderable box)))

let position_absolute renderable ~left ~top =
  ignore
    (expect_ok
       (O.Renderable.set_position_type renderable O.Yoga.Position_absolute));
  set_position renderable ~edge:O.Yoga.Left ~value:(O.Yoga.Point left);
  set_position renderable ~edge:O.Yoga.Top ~value:(O.Yoga.Point top)

let position_absolute_right renderable ~right ~top =
  ignore
    (expect_ok
       (O.Renderable.set_position_type renderable O.Yoga.Position_absolute));
  set_position renderable ~edge:O.Yoga.Right ~value:(O.Yoga.Point right);
  set_position renderable ~edge:O.Yoga.Top ~value:(O.Yoga.Point top)

let set_info demo content =
  ignore
    (expect_ok
       (Text.set_content demo.info_text
          (S.create [ S.chunk ~fg:(color "#e94560") content ])))

let update_opacity_labels demo =
  Array.iter
    (fun entry ->
      let content = Printf.sprintf "Opacity: %.1f" (Box.opacity entry.box) in
      ignore
        (expect_ok
           (Text.set_content entry.opacity_text
              (S.create [ S.chunk ~fg:O.Color.white content ]))))
    demo.boxes

let request_render demo = ignore (expect_ok (O.Renderer.request_render demo.renderer))

let release_live demo =
  Option.iter O.Renderer.release_live_lease demo.live_lease;
  demo.live_lease <- None

let stop_animation demo =
  demo.animating <- false;
  release_live demo

let start_animation demo =
  match O.Renderer.acquire_live_lease demo.renderer with
  | Error error -> invalid_arg (O.Error.message error)
  | Ok lease ->
      demo.phase <- 0.0;
      demo.animating <- true;
      demo.live_lease <- Some lease

let toggle_animation demo =
  if demo.animating then begin
    stop_animation demo;
    set_info demo "OPACITY DEMO | 1-4: Toggle opacity | A: Animate | Ctrl+C: Exit"
  end
  else begin
    start_animation demo;
    set_info demo "OPACITY DEMO | Animating... | A: Stop | Ctrl+C: Exit"
  end;
  request_render demo

let update_animation demo delta_seconds =
  if demo.animating then begin
    demo.phase <- demo.phase +. delta_seconds;
    Array.iteri
      (fun index entry ->
        let opacity =
          0.3 +. (0.7 *. Float.abs (sin (demo.phase +. (float_of_int index *. 0.5))))
        in
        ignore (expect_ok (Box.set_opacity entry.box opacity)))
      demo.boxes;
    update_opacity_labels demo
  end

let handle_key demo key_event =
  if Handler.key_event_kind key_event = Handler.Keypress then begin
    let modifiers = Handler.key_modifiers key_event in
    if not modifiers.ctrl && not modifiers.meta then
      match Handler.key key_event with
      | Key.Character bytes -> (
          match String.lowercase_ascii (Bytes.to_string bytes) with
          | "1" | "2" | "3" | "4" as value ->
              let index = int_of_string value - 1 in
              let entry = demo.boxes.(index) in
              let next = if Float.equal (Box.opacity entry.box) 1.0 then 0.3 else 1.0 in
              ignore (expect_ok (Box.set_opacity entry.box next));
              update_opacity_labels demo;
              request_render demo
          | "a" -> toggle_animation demo
          | _ -> ())
      | Key.Named _ -> ()
  end

let create_demo renderer =
  ignore
    (expect_ok
       (O.Renderer.set_background_color renderer ~color:(color "#1a1a2e")));
  let context = O.Renderer.context renderer in
  let header =
    expect_ok
      (Box.create context ~id:"opacity-demo-header"
         ~background_color:(color "#16213e")
         ~border_style:O.Lib.Border.Single ~border:Box.all_borders ())
  in
  let header_renderable = Box.as_renderable header in
  ignore (expect_ok (O.Renderable.set_width header_renderable (O.Yoga.Percent 100.0)));
  ignore (expect_ok (O.Renderable.set_height header_renderable (O.Yoga.Point 3.0)));
  ignore (expect_ok (O.Renderable.set_flex_shrink header_renderable (Some 0.0)));
  ignore (expect_ok (O.Renderable.set_align_items header_renderable O.Yoga.Align_center));
  ignore
    (expect_ok
       (O.Renderable.set_justify_content header_renderable O.Yoga.Justify_center));
  let info_text =
    styled_text context ~id:"opacity-demo-info" ~foreground:(color "#e94560")
      "OPACITY DEMO | 1-4: Toggle opacity | A: Animate | Ctrl+C: Exit"
  in
  add_child (Box.children header) info_text;

  let container =
    expect_ok
      (Box.create context ~id:"opacity-demo-container" ~should_fill:false ())
  in
  let container_renderable = Box.as_renderable container in
  ignore
    (expect_ok
       (O.Renderable.set_width container_renderable (O.Yoga.Percent 100.0)));
  ignore
    (expect_ok
       (O.Renderable.set_flex_grow container_renderable (Some 1.0)));
  ignore
    (expect_ok
       (O.Renderable.set_flex_shrink container_renderable (Some 1.0)));
  ignore
    (expect_ok
       (O.Renderable.set_flex_direction container_renderable O.Yoga.Flex_row));
  ignore
    (expect_ok
       (O.Renderable.set_align_items container_renderable O.Yoga.Align_center));
  ignore
    (expect_ok
       (O.Renderable.set_justify_content container_renderable O.Yoga.Justify_center));
  ignore
    (expect_ok
       (O.Renderable.set_padding container_renderable ~edge:O.Yoga.All
          (O.Yoga.Point 2.0)));

  let colors =
    [| color "#e94560"; color "#0f3460"; color "#533483"; color "#16a085" |]
  in
  let labels = [| "Box 1"; "Box 2"; "Box 3"; "Box 4" |] in
  let opacity_values = [| 1.0; 0.8; 0.5; 0.3 |] in
  let opacity_boxes =
    Array.mapi
      (fun index background ->
        let box =
          expect_ok
            (Box.create context ~id:(Printf.sprintf "box-%d" index)
               ~background_color:background
               ~border_style:O.Lib.Border.Double ~border:Box.all_borders
               ~border_color:O.Color.white ())
        in
        let renderable = Box.as_renderable box in
        position_absolute renderable ~left:(10.0 +. (float_of_int index *. 8.0))
          ~top:(5.0 +. (float_of_int index *. 2.0));
        set_layout renderable ~width:20.0 ~height:8.0;
        ignore
          (expect_ok
             (Box.set_opacity box opacity_values.(index)));
        set_centered_column renderable;
        let label =
          styled_text context ~id:(Printf.sprintf "label-%d" index)
            ~foreground:O.Color.white labels.(index)
        in
        let opacity_text =
          styled_text context ~id:(Printf.sprintf "opacity-%d" index)
            ~foreground:O.Color.white
            (Printf.sprintf "Opacity: %.1f" opacity_values.(index))
        in
        add_child (Box.children box) label;
        add_child (Box.children box) opacity_text;
        add_box_child (Box.children container) box;
        { box; opacity_text })
      colors
  in

  let nested_container =
    expect_ok
      (Box.create context ~id:"nested-container"
         ~background_color:(color "#e94560")
         ~border_style:O.Lib.Border.Single ~border:Box.all_borders ())
  in
  let nested_renderable = Box.as_renderable nested_container in
  position_absolute_right nested_renderable ~right:5.0 ~top:5.0;
  set_layout nested_renderable ~width:35.0 ~height:10.0;
  ignore (expect_ok (Box.set_opacity nested_container 0.7));
  ignore
    (expect_ok
       (O.Renderable.set_padding nested_renderable ~edge:O.Yoga.All
          (O.Yoga.Point 1.0)));
  ignore
    (expect_ok
       (O.Renderable.set_flex_direction nested_renderable O.Yoga.Flex_column));
  let nested_label =
    styled_text context ~id:"nested-label" ~foreground:O.Color.white
      "Parent: 0.7 opacity"
  in
  add_child (Box.children nested_container) nested_label;

  let nested_child =
    expect_ok
      (Box.create context ~id:"nested-child"
         ~background_color:(color "#0f3460")
         ~border_style:O.Lib.Border.Single ~border:Box.all_borders ())
  in
  let nested_child_renderable = Box.as_renderable nested_child in
  ignore
    (expect_ok
       (O.Renderable.set_width nested_child_renderable (O.Yoga.Percent 100.0)));
  ignore
    (expect_ok
       (O.Renderable.set_height nested_child_renderable (O.Yoga.Point 5.0)));
  ignore
    (expect_ok
       (O.Renderable.set_flex_shrink nested_child_renderable (Some 0.0)));
  ignore (expect_ok (Box.set_opacity nested_child 0.5));
  set_centered_column nested_child_renderable;
  let child_label =
    styled_text context ~id:"child-label" ~foreground:O.Color.white
      "Child: 0.5 opacity"
  in
  let effective_label =
    styled_text context ~id:"effective-label" ~foreground:(color "#ffcc00")
      "Effective: 0.35"
  in
  add_child (Box.children nested_child) child_label;
  add_child (Box.children nested_child) effective_label;
  add_box_child (Box.children nested_container) nested_child;
  add_box_child (Box.children container) nested_container;

  add_box_child (O.Renderer.children renderer) header;
  add_box_child (O.Renderer.children renderer) container;
  let demo =
    {
      renderer;
      info_text;
      boxes = opacity_boxes;
      phase = 0.0;
      animating = false;
      live_lease = None;
      pre_render = None;
    }
  in
  let pre_render =
    expect_ok
      (O.Renderer.attach_pre_render renderer (fun delta_seconds ->
           update_animation demo delta_seconds))
  in
  demo.pre_render <- Some pre_render;
  ignore
    (expect_ok
       (O.Renderer.on_keypress renderer (fun key_event ->
            handle_key demo key_event)));
  ignore
    (expect_ok
       (O.Renderer.attach_before_destroy renderer (fun () ->
            stop_animation demo;
            Option.iter O.Renderer.detach_pre_render demo.pre_render)));
  demo

let run renderer ~exit =
  let demo = create_demo renderer in
  (* Ctrl+C is owned by the shared harness-level binding; the opacity demo
     handles only its four toggles and animation key. *)
  Opentui_examples_lib.Standalone_keys.setup_common_demo_keys renderer ~on_ctrl_c:exit;
  ignore demo

let () =
  Eio_main.run @@ fun env ->
  let frames_per_second =
    match Sys.getenv_opt "OPENTUI_DEMO_FPS" with
    | Some raw -> (
        match int_of_string_opt raw with
        | Some value when value > 0 -> value
        | Some _ | None ->
            invalid_arg
              (Printf.sprintf
                 "OPENTUI_DEMO_FPS must be a positive integer, got %S" raw))
    | None -> 30
  in
  Opentui_examples_lib.App.run env ~frames_per_second
    ~init:(fun ~exit renderer -> run renderer ~exit)
