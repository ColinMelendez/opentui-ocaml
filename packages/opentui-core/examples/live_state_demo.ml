(* Port of vendor/opentui/packages/examples/src/live-state-demo.ts.

   Demonstrates the two live-rendering paths exposed by the retained renderer:
   renderer-level live requests and renderable-level [live] state. Renderable
   live state contributes to the renderer's live-request count only while the
   renderable is visible, so the visibility controls make that ownership
   relationship observable.

   The reference exposes [isRunning] and [currentControlState] directly. The
   OCaml renderer intentionally exposes the scheduler through explicit frame
   requests and live leases instead, so this demo derives the continuous
   [RUNNING]/[STOPPED] and [LIVE]/[ON-DEMAND] readouts from
   [live_request_count]. The harness process itself remains available while
   the renderer is stopped and waiting for an on-demand frame. *)

module O = Opentui_core
module S = O.Lib.Styled_text
module A = O.Lib.Text_attributes
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

module Palette = struct
  let background = color "#191e2d"
  let title = color "#ffd787"
  let instructions = color "#b0c4de"
  let status = color "#90ee90"
  let state = color "#ffff64"
  let white = O.Color.white
  let dim = color "#666666"
  let stopped = color "#f05f70"
  let renderer = color "#648cb4"
  let renderer_hover = color "#8bb2d6"
  let renderer_pressed = color "#3c5470"
  let renderable = color "#b4648c"
  let renderable_hover = color "#d889b0"
  let renderable_pressed = color "#6c3c54"
  let live = color "#8cb464"
  let live_hover = color "#b5dc86"
  let live_pressed = color "#54703c"
  let visibility = color "#b48c64"
  let visibility_hover = color "#d8b586"
  let visibility_pressed = color "#6c543c"
  let demo_background = color "#64c896"
  let demo_border = color "#96ffc8"
  let live_indicator = color "#00ffff"
end

type button = {
  box : Box.t;
  base_color : O.Color.t;
  hover_color : O.Color.t;
  pressed_color : O.Color.t;
  mutable hovered : bool;
}

type demo = {
  renderer : O.Renderer.t;
  root : Box.t;
  status_text : Text.t;
  renderer_state_text : Text.t;
  renderable_state_text : Text.t;
  exit : unit -> unit;
  mutable demo_renderable : Box.t option;
  mutable manual_live_requests : int;
  mutable frame_counter : int;
  mutable animation_counter : int;
  mutable pre_render : O.Renderer.pre_render_driver option;
  mutable key_subscription : O.Event_subscription.t option;
  mutable destroyed : bool;
}

let styled ?(attributes = A.none) ?fg text = S.chunk ?fg ~attributes text
let content chunks = S.create chunks

let add_child children renderable = ignore_ok (O.Layout_children.add children renderable)

let set_renderable renderable setter = ignore_ok (setter renderable)

let set_dimensions renderable ~width ~height =
  set_renderable renderable (fun value -> O.Renderable.set_width value width);
  set_renderable renderable (fun value -> O.Renderable.set_height value height)

let position_absolute renderable ~left ~top ~z_index =
  set_renderable renderable (fun value ->
      O.Renderable.set_position_type value O.Yoga.Position_absolute);
  set_renderable renderable (fun value ->
      O.Renderable.set_position value ~edge:O.Yoga.Left (O.Yoga.Point left));
  set_renderable renderable (fun value ->
      O.Renderable.set_position value ~edge:O.Yoga.Top (O.Yoga.Point top));
  set_renderable renderable (fun value -> O.Renderable.set_z_index value z_index)

let set_flex_center renderable =
  set_renderable renderable (fun value ->
      O.Renderable.set_flex_direction value O.Yoga.Flex_row);
  set_renderable renderable (fun value ->
      O.Renderable.set_align_items value O.Yoga.Align_center);
  set_renderable renderable (fun value ->
      O.Renderable.set_justify_content value O.Yoga.Justify_center)

let make_text context ?id styled_content =
  expect_ok (Text.create context ?id ~content:styled_content ())

let add_absolute_text context parent ~id ~text_content ~left ~top ~foreground
    ~attributes =
  let text =
    make_text context ~id
      (content [ styled ~fg:foreground ~attributes text_content ])
  in
  let renderable = Text.as_renderable text in
  position_absolute renderable ~left ~top ~z_index:1000;
  add_child (Box.children parent) renderable;
  text

let update_button_background button color = ignore_ok (Box.set_background_color button.box color)

let make_button context parent ~id ~label ~left ~top ~base_color ~hover_color
    ~pressed_color action =
  let box = expect_ok (Box.create context ~id ~background_color:base_color ()) in
  let renderable = Box.as_renderable box in
  position_absolute renderable ~left ~top ~z_index:100;
  set_dimensions renderable ~width:(O.Yoga.Point 20.0) ~height:(O.Yoga.Point 3.0);
  set_flex_center renderable;
  let label_text =
    make_text context ~id:(id ^ "-label")
      (content [ styled ~attributes:A.bold ~fg:Palette.white label ])
  in
  let label_renderable = Text.as_renderable label_text in
  set_renderable label_renderable (fun value ->
      O.Renderable.set_flex_grow value (Some 0.0));
  set_renderable label_renderable (fun value ->
      O.Renderable.set_flex_shrink value (Some 0.0));
  add_child (Box.children box) label_renderable;
  let button =
    { box; base_color; hover_color; pressed_color; hovered = false }
  in
  set_renderable renderable (fun value ->
      O.Renderable.set_on_mouse_over value
        (Some (fun event ->
             ignore event;
             button.hovered <- true;
             update_button_background button button.hover_color)));
  set_renderable renderable (fun value ->
      O.Renderable.set_on_mouse_out value
        (Some (fun event ->
             ignore event;
             button.hovered <- false;
             update_button_background button button.base_color)));
  set_renderable renderable (fun value ->
      O.Renderable.set_on_mouse_down value
        (Some (fun event ->
             if Int.equal (O.Renderable.mouse_button event) 0 then begin
               update_button_background button button.pressed_color;
               action ();
               O.Renderable.mouse_stop_propagation event
             end)));
  set_renderable renderable (fun value ->
      O.Renderable.set_on_mouse_up value
        (Some (fun event ->
             if Int.equal (O.Renderable.mouse_button event) 0 then begin
               update_button_background button
                 (if button.hovered then button.hover_color else button.base_color);
               O.Renderable.mouse_stop_propagation event
             end)));
  add_child (Box.children parent) renderable;
  button

let timestamp () =
  let time = Unix.localtime (Unix.gettimeofday ()) in
  Printf.sprintf "%02d:%02d:%02d" time.Unix.tm_hour time.Unix.tm_min
    time.Unix.tm_sec

let update_status demo message =
  ignore_ok
    (Text.set_content demo.status_text
       (content [ styled ~fg:Palette.status ("[" ^ timestamp () ^ "] " ^ message) ]))

let update_renderer_state demo =
  let live_count = expect_ok (O.Renderer.live_request_count demo.renderer) in
  let live_active = Int.compare live_count 0 > 0 in
  let indicator =
    if live_active then
      let indicators = [| "▘"; "▝"; "▗"; "▖" |] in
      indicators.(demo.animation_counter mod Array.length indicators)
    else " "
  in
  let state_color = if live_active then Palette.live else Palette.renderer in
  let running_color = if live_active then Palette.live else Palette.stopped in
  let running_state = if live_active then "RUNNING" else "STOPPED" in
  let control_state = if live_active then "LIVE" else "ON-DEMAND" in
  ignore_ok
    (Text.set_content demo.renderer_state_text
       (content
          [ styled ~attributes:A.bold "Renderer State:";
            styled " ";
            styled ~attributes:A.bold ~fg:running_color running_state;
            styled " | ";
            styled ~attributes:A.bold "Live Requests:";
            styled " ";
            styled ~attributes:A.bold ~fg:state_color (string_of_int live_count);
            styled ~fg:Palette.live_indicator (" " ^ indicator);
            styled " | ";
            styled ~attributes:A.bold "Control State:";
            styled " ";
            styled ~attributes:A.bold ~fg:state_color control_state;
            styled " | ";
            styled ~attributes:A.bold "Frame:";
            styled ~fg:Palette.dim (" " ^ string_of_int demo.frame_counter) ]))

let update_renderable_state demo =
  let exists, live, visible =
    match demo.demo_renderable with
    | None -> false, false, false
    | Some box ->
        let renderable = Box.as_renderable box in
        true, O.Renderable.live renderable, O.Renderable.visible renderable
  in
  let exists_color = if exists then Palette.live else Palette.dim in
  let live_color = if live then Palette.live else Palette.visibility in
  let visible_color = if visible then Palette.renderer else Palette.dim in
  ignore_ok
    (Text.set_content demo.renderable_state_text
       (content
          [ styled ~attributes:A.bold "Demo Renderable:";
            styled " ";
            styled ~attributes:A.bold ~fg:exists_color
              (if exists then "ADDED" else "NOT ADDED");
            styled " | ";
            styled ~attributes:A.bold "Live:";
            styled " ";
            styled ~attributes:A.bold ~fg:live_color
              (if live then "TRUE" else "FALSE");
            styled " | ";
            styled ~attributes:A.bold "Visible:";
            styled " ";
            styled ~attributes:A.bold ~fg:visible_color
              (if visible then "TRUE" else "FALSE") ]))

let refresh_state demo =
  update_renderer_state demo;
  update_renderable_state demo

let add_demo_renderable demo =
  match demo.demo_renderable with
  | Some _ ->
      update_status demo "Demo renderable already exists!";
      refresh_state demo
  | None ->
      let context = O.Renderer.context demo.renderer in
      let box =
        expect_ok
          (Box.create context ~id:"live-state-demo-renderable"
             ~background_color:Palette.demo_background
             ~border_style:O.Lib.Border.Double ~border:Box.all_borders
             ~border_color:Palette.demo_border ~title:" Demo Renderable "
             ~title_alignment:O.Lib.Border.Center ())
      in
      position_absolute (Box.as_renderable box) ~left:60.0 ~top:15.0 ~z_index:50;
      set_dimensions (Box.as_renderable box) ~width:(O.Yoga.Point 30.0)
        ~height:(O.Yoga.Point 8.0);
      add_child (Box.children demo.root) (Box.as_renderable box);
      demo.demo_renderable <- Some box;
      update_status demo "Added demo renderable";
      refresh_state demo

let remove_demo_renderable demo =
  match demo.demo_renderable with
  | None ->
      update_status demo "No demo renderable to remove!";
      refresh_state demo
  | Some box ->
      ignore_ok
        (O.Layout_children.remove (Box.children demo.root) (Box.as_renderable box));
      Box.destroy_recursively box;
      demo.demo_renderable <- None;
      update_status demo "Removed demo renderable";
      refresh_state demo

let set_demo_live demo value =
  match demo.demo_renderable with
  | None ->
      update_status demo "No demo renderable to set live!";
      refresh_state demo
  | Some box ->
      ignore_ok (O.Renderable.set_live (Box.as_renderable box) value);
      update_status demo
        (if value then "Set demo renderable live = true"
         else "Set demo renderable live = false");
      refresh_state demo

let set_demo_visible demo value =
  match demo.demo_renderable with
  | None ->
      update_status demo "No demo renderable to set visible!";
      refresh_state demo
  | Some box ->
      ignore_ok (Box.set_visible box value);
      update_status demo
        (if value then "Set demo renderable visible = true"
         else "Set demo renderable visible = false");
      refresh_state demo

let request_live demo =
  ignore_ok (O.Renderer.request_live demo.renderer);
  demo.manual_live_requests <- demo.manual_live_requests + 1;
  update_status demo "Manually requested live";
  refresh_state demo

let drop_live demo =
  ignore_ok (O.Renderer.drop_live demo.renderer);
  if Int.compare demo.manual_live_requests 0 > 0 then
    demo.manual_live_requests <- demo.manual_live_requests - 1;
  update_status demo "Manually dropped live";
  refresh_state demo

let handle_key demo key_event =
  match Handler.key_event_kind key_event with
  | Handler.Keypress ->
      let modifiers = Handler.key_modifiers key_event in
      if not modifiers.ctrl && not modifiers.meta then begin
        match Handler.key key_event with
        | Key.Named Key.Escape -> demo.exit ()
        | Key.Character _ | Key.Named _ -> ()
      end
  | Handler.Keyrelease | Handler.Paste -> ()

let build_layout renderer ~exit =
  ignore_ok (O.Renderer.set_background_color renderer ~color:Palette.background);
  let context = O.Renderer.context renderer in
  let root =
    expect_ok
      (Box.create context ~id:"live-state-demo-root"
         ~background_color:Palette.background ())
  in
  let root_renderable = Box.as_renderable root in
  set_renderable root_renderable (fun value -> O.Renderable.set_flex_grow value (Some 1.0));
  set_renderable root_renderable (fun value ->
      O.Renderable.set_width value (O.Yoga.Percent 100.0));
  set_renderable root_renderable (fun value ->
      O.Renderable.set_height value (O.Yoga.Percent 100.0));
  set_renderable root_renderable (fun value ->
      O.Renderable.set_max_width value (O.Yoga.Percent 100.0));
  set_renderable root_renderable (fun value ->
      O.Renderable.set_max_height value (O.Yoga.Percent 100.0));
  add_child (O.Renderer.children renderer) root_renderable;
  let title_text =
    add_absolute_text context root ~id:"live-state-demo-title"
      ~text_content:"Live State Management Demo" ~left:2.0 ~top:1.0
      ~foreground:Palette.title ~attributes:A.bold
  in
  ignore title_text;
  let instructions_text =
    add_absolute_text context root ~id:"live-state-demo-instructions"
      ~text_content:"Test the live state management system • Escape: exit demo"
      ~left:2.0 ~top:2.0 ~foreground:Palette.instructions ~attributes:A.none
  in
  ignore instructions_text;
  let status_text =
    add_absolute_text context root ~id:"live-state-demo-status"
      ~text_content:"Ready - Click buttons to test live state management" ~left:2.0
      ~top:4.0 ~foreground:Palette.status ~attributes:A.italic
  in
  let renderer_state_text =
    add_absolute_text context root ~id:"live-state-demo-renderer-state" ~text_content:""
      ~left:2.0 ~top:6.0 ~foreground:Palette.state ~attributes:A.none
  in
  let renderable_state_text =
    add_absolute_text context root ~id:"live-state-demo-renderable-state" ~text_content:""
      ~left:2.0 ~top:7.0 ~foreground:Palette.state ~attributes:A.none
  in
  let demo =
    {
      renderer;
      root;
      status_text;
      renderer_state_text;
      renderable_state_text;
      exit;
      demo_renderable = None;
      manual_live_requests = 0;
      frame_counter = 0;
      animation_counter = 0;
      pre_render = None;
      key_subscription = None;
      destroyed = false;
    }
  in
  let start_y = 10.0 in
  let spacing = 22.0 in
  ignore
    (make_button context root ~id:"request-live" ~label:"REQUEST LIVE"
       ~left:2.0 ~top:start_y ~base_color:Palette.renderer
       ~hover_color:Palette.renderer_hover ~pressed_color:Palette.renderer_pressed
       (fun () -> request_live demo));
  ignore
    (make_button context root ~id:"drop-live" ~label:"DROP LIVE"
       ~left:(2.0 +. spacing) ~top:start_y ~base_color:Palette.renderer
       ~hover_color:Palette.renderer_hover ~pressed_color:Palette.renderer_pressed
       (fun () -> drop_live demo));
  ignore
    (make_button context root ~id:"add-renderable" ~label:"ADD RENDERABLE"
       ~left:2.0 ~top:(start_y +. 5.0) ~base_color:Palette.renderable
       ~hover_color:Palette.renderable_hover ~pressed_color:Palette.renderable_pressed
       (fun () -> add_demo_renderable demo));
  ignore
    (make_button context root ~id:"remove-renderable" ~label:"REMOVE RENDERABLE"
       ~left:(2.0 +. spacing) ~top:(start_y +. 5.0)
       ~base_color:Palette.renderable ~hover_color:Palette.renderable_hover
       ~pressed_color:Palette.renderable_pressed
       (fun () -> remove_demo_renderable demo));
  ignore
    (make_button context root ~id:"set-live-true" ~label:"LIVE = TRUE"
       ~left:2.0 ~top:(start_y +. 10.0) ~base_color:Palette.live
       ~hover_color:Palette.live_hover ~pressed_color:Palette.live_pressed
       (fun () -> set_demo_live demo true));
  ignore
    (make_button context root ~id:"set-live-false" ~label:"LIVE = FALSE"
       ~left:(2.0 +. spacing) ~top:(start_y +. 10.0) ~base_color:Palette.live
       ~hover_color:Palette.live_hover ~pressed_color:Palette.live_pressed
       (fun () -> set_demo_live demo false));
  ignore
    (make_button context root ~id:"set-visible-true" ~label:"VISIBLE = TRUE"
       ~left:2.0 ~top:(start_y +. 15.0) ~base_color:Palette.visibility
       ~hover_color:Palette.visibility_hover
       ~pressed_color:Palette.visibility_pressed
       (fun () -> set_demo_visible demo true));
  ignore
    (make_button context root ~id:"set-visible-false" ~label:"VISIBLE = FALSE"
       ~left:(2.0 +. spacing) ~top:(start_y +. 15.0)
       ~base_color:Palette.visibility ~hover_color:Palette.visibility_hover
       ~pressed_color:Palette.visibility_pressed
       (fun () -> set_demo_visible demo false));
  ignore
    (add_absolute_text context root ~id:"live-state-demo-renderer-label"
       ~text_content:"Renderer Control:" ~left:2.0 ~top:(start_y -. 1.0)
       ~foreground:Palette.renderer ~attributes:A.bold);
  ignore
    (add_absolute_text context root ~id:"live-state-demo-renderable-label"
       ~text_content:"Renderable Management:" ~left:2.0 ~top:(start_y +. 4.0)
       ~foreground:Palette.renderable ~attributes:A.bold);
  ignore
    (add_absolute_text context root ~id:"live-state-demo-live-label"
       ~text_content:"Live State Control:" ~left:2.0 ~top:(start_y +. 9.0)
       ~foreground:Palette.live ~attributes:A.bold);
  ignore
    (add_absolute_text context root ~id:"live-state-demo-visibility-label"
       ~text_content:"Visibility Control:" ~left:2.0 ~top:(start_y +. 14.0)
       ~foreground:Palette.visibility ~attributes:A.bold);
  let pre_render =
    expect_ok
      (O.Renderer.attach_pre_render renderer (fun delta_seconds ->
           ignore delta_seconds;
           if not demo.destroyed then begin
             demo.frame_counter <- demo.frame_counter + 1;
             if Int.equal (demo.frame_counter mod 10) 0 then begin
               demo.animation_counter <- demo.animation_counter + 1;
               update_renderer_state demo;
               update_renderable_state demo
             end
           end))
  in
  demo.pre_render <- Some pre_render;
  update_renderer_state demo;
  update_renderable_state demo;
  demo

let destroy demo =
  if not demo.destroyed then begin
    demo.destroyed <- true;
    Option.iter O.Event_subscription.cancel demo.key_subscription;
    Option.iter O.Renderer.detach_pre_render demo.pre_render;
    while Int.compare demo.manual_live_requests 0 > 0 do
      ignore_ok (O.Renderer.drop_live demo.renderer);
      demo.manual_live_requests <- demo.manual_live_requests - 1
    done;
    demo.manual_live_requests <- 0;
    ignore_ok
      (O.Layout_children.remove (O.Renderer.children demo.renderer)
         (Box.as_renderable demo.root));
    Box.destroy_recursively demo.root;
    demo.demo_renderable <- None;
    demo.key_subscription <- None;
    demo.pre_render <- None
  end

let run renderer ~exit ~copy_to_clipboard =
  ignore copy_to_clipboard;
  let demo = build_layout renderer ~exit in
  let key_subscription = expect_ok (O.Renderer.on_keypress renderer (handle_key demo)) in
  demo.key_subscription <- Some key_subscription;
  ignore_ok (O.Renderer.attach_before_destroy renderer (fun () -> destroy demo));
  Opentui_examples_lib.Standalone_keys.setup_common_demo_keys renderer ~on_ctrl_c:exit

let () =
  Eio_main.run @@ fun env ->
  Opentui_examples_lib.App.run env ~target_frames_per_second:30
    ~init:(fun ~exit ~copy_to_clipboard renderer ->
      run renderer ~exit ~copy_to_clipboard)
