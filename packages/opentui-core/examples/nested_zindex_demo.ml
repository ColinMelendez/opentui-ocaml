(* Port of vendor/opentui/packages/examples/src/nested-zindex-demo.ts.

   The visible boxes are children of three full-screen parent groups.  The
   animation changes the groups' z-indices while keeping their child
   z-indices fixed, making the distinction between group order and in-group
   order visible in the overlapping boxes. *)

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

let ignore_ok result = ignore (expect_ok result)
let color = Util.color_of_hex

let attach children renderable = ignore_ok (O.Layout_children.add children renderable)

let set_position_absolute renderable ~left ~top ~z_index =
  ignore_ok
    (O.Renderable.set_position_type renderable O.Yoga.Position_absolute);
  ignore_ok
    (O.Renderable.set_position renderable ~edge:O.Yoga.Left
       (O.Yoga.Point left));
  ignore_ok
    (O.Renderable.set_position renderable ~edge:O.Yoga.Top
       (O.Yoga.Point top));
  ignore_ok (O.Renderable.set_z_index renderable z_index)

let set_dimensions renderable ~width ~height =
  ignore_ok (O.Renderable.set_width renderable (O.Yoga.Point width));
  ignore_ok (O.Renderable.set_height renderable (O.Yoga.Point height))

let set_full_screen renderable =
  ignore_ok (O.Renderable.set_width renderable (O.Yoga.Percent 100.0));
  ignore_ok (O.Renderable.set_height renderable (O.Yoga.Percent 100.0));
  ignore_ok (O.Renderable.set_flex_shrink renderable (Some 0.0))

let styled_content ~foreground ~attributes content =
  S.create [ S.chunk ~fg:foreground ~attributes content ]

let add_text context parent ~id ~content ~left ~top ~foreground ~attributes
    ~z_index =
  let text =
    expect_ok
      (Text.create context ~id ~wrap_mode:O.Text_buffer_view.No_wrap
         ~content:(styled_content ~foreground ~attributes content) ())
  in
  set_position_absolute (Text.as_renderable text) ~left ~top ~z_index;
  attach (Box.children parent) (Text.as_renderable text);
  text

let add_box context parent ~id ~left ~top ~width ~height ~background_color
    ~border_style ~border_color ?title ?title_alignment ~z_index () =
  let box =
    expect_ok
      (Box.create context ~id ~background_color ~border_style
         ~border:Box.all_borders ~border_color ?title ?title_alignment ())
  in
  let renderable = Box.as_renderable box in
  set_position_absolute renderable ~left ~top ~z_index;
  set_dimensions renderable ~width ~height;
  attach (Box.children parent) renderable;
  box

let create_layer context parent ~id ~z_index =
  (* The reference leaves these absolute grouping nodes unsized.  Local Box
     renderables use their measured bounds as a child scissor, so make each
     grouping node fill its parent while keeping its own fill invisible. *)
  let layer = expect_ok (Box.create context ~id ~should_fill:false ()) in
  let renderable = Box.as_renderable layer in
  set_position_absolute renderable ~left:0.0 ~top:0.0 ~z_index;
  set_full_screen renderable;
  ignore_ok (Box.set_visible layer true);
  attach (Box.children parent) renderable;
  layer

type phase_config = {
  a_z_index : int;
  b_z_index : int;
  c_z_index : int;
  name : string;
}

let phase_config = function
  | 0 ->
      { a_z_index = 100; b_z_index = 50; c_z_index = 20;
        name = "Original Hierarchy" }
  | 1 ->
      { a_z_index = 50; b_z_index = 20; c_z_index = 100;
        name = "C Group on Top" }
  | 2 ->
      { a_z_index = 20; b_z_index = 100; c_z_index = 50;
        name = "B Group on Top" }
  | _ ->
      { a_z_index = 60; b_z_index = 60; c_z_index = 60;
        name = "Equal Parents (Child z-index matters)" }

type demo = {
  renderer : O.Renderer.t;
  parent_container : Box.t;
  group_a : Box.t;
  group_b : Box.t;
  group_c : Box.t;
  parent_a : Box.t;
  parent_b : Box.t;
  parent_c : Box.t;
  phase_indicator : Text.t;
  z_index_display : Text.t;
  mutable phase : int;
  mutable animation_speed_ms : int;
  live_lease : O.Renderer.live_lease;
  mutable pre_render : O.Renderer.pre_render_driver option;
  mutable key_subscription : O.Event_subscription.t option;
  mutable destroyed : bool;
}

let set_text text ~foreground ~attributes content =
  ignore_ok
    (Text.set_content text (styled_content ~foreground ~attributes content))

let apply_phase demo phase =
  let config = phase_config phase in
  ignore_ok (Box.set_z_index demo.group_a config.a_z_index);
  ignore_ok (Box.set_z_index demo.group_b config.b_z_index);
  ignore_ok (Box.set_z_index demo.group_c config.c_z_index);
  ignore_ok
    (Box.set_title demo.parent_a
       (Some (Printf.sprintf "Parent A (z=%d)" config.a_z_index)));
  ignore_ok
    (Box.set_title demo.parent_b
       (Some (Printf.sprintf "Parent B (z=%d)" config.b_z_index)));
  ignore_ok
    (Box.set_title demo.parent_c
       (Some (Printf.sprintf "Parent C (z=%d)" config.c_z_index)));
  set_text demo.phase_indicator ~foreground:O.Color.white
    ~attributes:(O.Lib.Text_attributes.of_flags ~bold:true ())
    (Printf.sprintf "Animation Phase: %d/4 - %s" (phase + 1) config.name);
  set_text demo.z_index_display ~foreground:O.Color.white
    ~attributes:O.Lib.Text_attributes.none
    (Printf.sprintf "Current Z-Indices - A:%d, B:%d, C:%d" config.a_z_index
       config.b_z_index config.c_z_index)

let update_animation demo delta_seconds =
  ignore delta_seconds;
  let speed_ms = float_of_int demo.animation_speed_ms in
  let cycle_ms = speed_ms *. 4.0 in
  let elapsed_ms = mod_float (Unix.gettimeofday () *. 1000.0) cycle_ms in
  let phase = int_of_float (Float.floor (elapsed_ms /. speed_ms)) in
  if not (Int.equal phase demo.phase) then begin
    demo.phase <- phase;
    apply_phase demo phase
  end

let handle_key demo key_event =
  if not demo.destroyed then
    match Handler.key_event_kind key_event with
    | Handler.Keypress ->
        (match Handler.key key_event with
         | Key.Character bytes ->
             let value = Bytes.to_string bytes in
             if String.equal value "+" || String.equal value "=" then
               demo.animation_speed_ms <-
                 Int.max 500 (demo.animation_speed_ms - 200)
             else if String.equal value "-" || String.equal value "_" then
               demo.animation_speed_ms <-
                 Int.min 5000 (demo.animation_speed_ms + 200)
         | Key.Named _ -> ())
    | Handler.Keyrelease | Handler.Paste -> ()

let create_demo renderer =
  let context = O.Renderer.context renderer in
  ignore_ok
    (O.Renderer.set_background_color renderer ~color:(color "#001122"));
  let parent_container =
    expect_ok (Box.create context ~id:"parent-container" ~should_fill:false ())
  in
  let parent_renderable = Box.as_renderable parent_container in
  set_full_screen parent_renderable;
  ignore_ok (Box.set_z_index parent_container 10);
  attach (O.Renderer.children renderer) parent_renderable;

  let title_attributes =
    O.Lib.Text_attributes.of_flags ~bold:true ~underline:true ()
  in
  ignore
    (add_text context parent_container ~id:"main-title"
       ~content:"Nested Render Objects & Z-Index Demo" ~left:10.0 ~top:2.0
       ~foreground:(color "#FFFF00") ~attributes:title_attributes ~z_index:1000);

  let group_a = create_layer context parent_container ~id:"parent-group-a" ~z_index:100 in
  let group_b = create_layer context parent_container ~id:"parent-group-b" ~z_index:50 in
  let group_c = create_layer context parent_container ~id:"parent-group-c" ~z_index:20 in

  let parent_a =
    add_box context group_a ~id:"box-a1" ~left:15.0 ~top:8.0 ~width:25.0
      ~height:6.0 ~background_color:(color "#220044")
      ~border_style:O.Lib.Border.Single ~border_color:(color "#FF44FF")
      ~title:"Parent A (z=100)" ~title_alignment:O.Lib.Border.Center ~z_index:10
      ()
  in
  ignore
    (add_text context group_a ~id:"text-a1" ~content:"Child A1 (z=10)"
       ~left:17.0 ~top:10.0 ~foreground:(color "#FF44FF")
       ~attributes:(O.Lib.Text_attributes.of_flags ~bold:true ()) ~z_index:10);
  ignore
    (add_box context group_a ~id:"box-a2" ~left:20.0 ~top:11.0 ~width:15.0
       ~height:4.0 ~background_color:(color "#440044")
       ~border_style:O.Lib.Border.Single ~border_color:(color "#FF88FF")
       ~z_index:5 ());
  ignore
    (add_text context group_a ~id:"text-a2" ~content:"Child A2 (z=5)"
       ~left:22.0 ~top:12.0 ~foreground:(color "#FF88FF")
       ~attributes:O.Lib.Text_attributes.none ~z_index:5);

  let parent_b =
    add_box context group_b ~id:"box-b1" ~left:30.0 ~top:12.0 ~width:25.0
      ~height:6.0 ~background_color:(color "#004422")
      ~border_style:O.Lib.Border.Double ~border_color:(color "#44FF44")
      ~title:"Parent B (z=50)" ~title_alignment:O.Lib.Border.Center ~z_index:20
      ()
  in
  ignore
    (add_text context group_b ~id:"text-b1" ~content:"Child B1 (z=20)"
       ~left:32.0 ~top:14.0 ~foreground:(color "#44FF44")
       ~attributes:(O.Lib.Text_attributes.of_flags ~bold:true ()) ~z_index:20);
  ignore
    (add_box context group_b ~id:"box-b2" ~left:35.0 ~top:15.0 ~width:15.0
       ~height:4.0 ~background_color:(color "#004400")
       ~border_style:O.Lib.Border.Single ~border_color:(color "#88FF88")
       ~z_index:15 ());
  ignore
    (add_text context group_b ~id:"text-b2" ~content:"Child B2 (z=15)"
       ~left:37.0 ~top:16.0 ~foreground:(color "#88FF88")
       ~attributes:O.Lib.Text_attributes.none ~z_index:15);

  let parent_c =
    add_box context group_c ~id:"box-c1" ~left:45.0 ~top:16.0 ~width:25.0
      ~height:6.0 ~background_color:(color "#442200")
      ~border_style:O.Lib.Border.Rounded ~border_color:(color "#FFFF44")
      ~title:"Parent C (z=20)" ~title_alignment:O.Lib.Border.Center ~z_index:30
      ()
  in
  ignore
    (add_text context group_c ~id:"text-c1" ~content:"Child C1 (z=30)"
       ~left:47.0 ~top:18.0 ~foreground:(color "#FFFF44")
       ~attributes:(O.Lib.Text_attributes.of_flags ~bold:true ()) ~z_index:30);
  ignore
    (add_box context group_c ~id:"box-c2" ~left:50.0 ~top:19.0 ~width:15.0
       ~height:4.0 ~background_color:(color "#444400")
       ~border_style:O.Lib.Border.Single ~border_color:(color "#FFFF88")
       ~z_index:25 ());
  ignore
    (add_text context group_c ~id:"text-c2" ~content:"Child C2 (z=25)"
       ~left:52.0 ~top:20.0 ~foreground:(color "#FFFF88")
       ~attributes:O.Lib.Text_attributes.none ~z_index:25);

  let muted = color "#AAAAAA" in
  ignore
    (add_text context parent_container ~id:"explanation1"
       ~content:
         "Key Concept: Parent z-index determines group layering, child z-index determines order within group"
       ~left:10.0 ~top:25.0 ~foreground:muted
       ~attributes:O.Lib.Text_attributes.none ~z_index:1000);
  ignore
    (add_text context parent_container ~id:"explanation2"
       ~content:
         "Even if Child C1 has z=30, it renders behind Parent A & B because Parent C has z=20"
       ~left:10.0 ~top:26.0 ~foreground:muted
       ~attributes:O.Lib.Text_attributes.none ~z_index:1000);
  let phase_indicator =
    add_text context parent_container ~id:"phase-indicator"
      ~content:"Animation Phase: 1/4" ~left:10.0 ~top:28.0
      ~foreground:O.Color.white
      ~attributes:(O.Lib.Text_attributes.of_flags ~bold:true ()) ~z_index:1000
  in
  let z_index_display =
    add_text context parent_container ~id:"zindex-display"
      ~content:"Current Z-Indices - A:100, B:50, C:20" ~left:10.0 ~top:29.0
      ~foreground:O.Color.white ~attributes:O.Lib.Text_attributes.none
      ~z_index:1000
  in
  let live_lease = expect_ok (O.Renderer.acquire_live_lease renderer) in
  let demo =
    {
      renderer;
      parent_container;
      group_a;
      group_b;
      group_c;
      parent_a;
      parent_b;
      parent_c;
      phase_indicator;
      z_index_display;
      phase = 0;
      animation_speed_ms = 2000;
      live_lease;
      pre_render = None;
      key_subscription = None;
      destroyed = false;
    }
  in
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
  demo

let destroy demo =
  if not demo.destroyed then begin
    demo.destroyed <- true;
    Option.iter O.Event_subscription.cancel demo.key_subscription;
    Option.iter O.Renderer.detach_pre_render demo.pre_render;
    O.Renderer.release_live_lease demo.live_lease;
    ignore_ok
      (O.Layout_children.remove (O.Renderer.children demo.renderer)
         (Box.as_renderable demo.parent_container));
    Box.destroy_recursively demo.parent_container;
    ignore_ok
      (O.Renderer.set_cursor_position demo.renderer ~x:0l ~y:0l ~visible:false ());
    demo.key_subscription <- None;
    demo.pre_render <- None
  end

let run renderer ~exit ~copy_to_clipboard =
  ignore copy_to_clipboard;
  let demo = create_demo renderer in
  ignore_ok
    (O.Renderer.attach_before_destroy renderer (fun () -> destroy demo));
  Opentui_examples_lib.Standalone_keys.setup_common_demo_keys renderer
    ~on_ctrl_c:exit

let () =
  Eio_main.run @@ fun env ->
  Opentui_examples_lib.App.run env ~target_frames_per_second:30
    ~init:(fun ~exit ~copy_to_clipboard renderer ->
      run renderer ~exit ~copy_to_clipboard)
