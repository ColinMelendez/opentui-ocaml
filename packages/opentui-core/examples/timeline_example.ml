(* Port of vendor/opentui/packages/examples/src/timeline-example.ts.

   The example uses the core timeline, property-binding, easing, and
   synchronized-child APIs directly while rendering the animated values into
   the retained Box and Text primitives. *)

module O = Opentui_core
module S = O.Lib.Styled_text
module Box = O.Renderables.Box
module Text = O.Renderables.Text
module Animation = O.Animation
module Timeline = Animation.Timeline
module Property = Animation.Property
module Easing = Animation.Easing
module Key = O.Lib.Key_decoder
module Handler = O.Lib.Key_handler
module Util = Opentui_examples_lib.Util

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> invalid_arg (O.Error.message error)

let expect_animation_ok result =
  match result with
  | Ok value -> value
  | Error error -> invalid_arg (Animation.Error.message error)

let expect_animation_update result =
  match result with
  | Ok () -> ()
  | Error fault -> invalid_arg (Animation.Error.fault_message fault)

let color = Util.color_of_hex

let set_position_absolute renderable ~left ~top ~z_index =
  ignore
    (expect_ok
       (O.Renderable.set_position_type renderable O.Yoga.Position_absolute));
  ignore
    (expect_ok
       (O.Renderable.set_position renderable ~edge:O.Yoga.Left
          (O.Yoga.Point left)));
  ignore
    (expect_ok
       (O.Renderable.set_position renderable ~edge:O.Yoga.Top
          (O.Yoga.Point top)));
  ignore (expect_ok (O.Renderable.set_z_index renderable z_index))

let set_dimensions renderable ~width ~height =
  ignore (expect_ok (O.Renderable.set_width renderable (O.Yoga.Point width)));
  ignore (expect_ok (O.Renderable.set_height renderable (O.Yoga.Point height)))

let attach children renderable =
  ignore (expect_ok (O.Layout_children.add children renderable))

let add_bordered_box context parent ~id ~left ~top ~width ~height
    ~background_color ~title ~title_alignment ~z_index =
  let box =
    expect_ok
      (Box.create context ~id ~background_color
         ~border_style:O.Lib.Border.Single ~border:Box.all_borders
         ~border_color:O.Color.white ~title ~title_alignment ())
  in
  let renderable = Box.as_renderable box in
  set_position_absolute renderable ~left ~top ~z_index;
  set_dimensions renderable ~width ~height;
  attach (Box.children parent) renderable;
  box

let add_plain_box context parent ~id ~left ~top ~width ~height
    ~background_color ~z_index =
  let box = expect_ok (Box.create context ~id ~background_color ()) in
  let renderable = Box.as_renderable box in
  set_position_absolute renderable ~left ~top ~z_index;
  set_dimensions renderable ~width ~height;
  attach (Box.children parent) renderable;
  box

let add_text context parent ~id ~left ~top ~foreground ~content ~z_index =
  let text =
    expect_ok
      (Text.create context ~id
         ~content:(S.create [ S.chunk ~fg:foreground content ]) ())
  in
  set_position_absolute (Text.as_renderable text) ~left ~top ~z_index;
  attach (Box.children parent) (Text.as_renderable text);
  text

let set_text text ~foreground content =
  ignore
    (expect_ok
       (Text.set_content text (S.create [ S.chunk ~fg:foreground content ])))

let set_box_width box width =
  ignore (expect_ok (Box.set_width box (O.Yoga.Point (float_of_int width))))

let set_box_height box height =
  ignore (expect_ok (Box.set_height box (O.Yoga.Point (float_of_int height))))

let set_box_position box ~x ~y =
  let renderable = Box.as_renderable box in
  ignore
    (expect_ok
       (O.Renderable.set_position renderable ~edge:O.Yoga.Left
          (O.Yoga.Point (float_of_int x))));
  ignore
    (expect_ok
       (O.Renderable.set_position renderable ~edge:O.Yoga.Top
          (O.Yoga.Point (float_of_int y))))

let set_box_rgb box red green blue =
  ignore
    (expect_ok
       (Box.set_background_color box
          (color (Util.hex_of_rgb red green blue))))

let javascript_round value = int_of_float (Float.floor (value +. 0.5))

type visuals = {
  renderer : O.Renderer.t;
  parent : Box.t;
  box_object : Box.t;
  color_object : Box.t;
  physics_object : Box.t;
  alternating_object : Box.t;
  status_line1 : Text.t;
  status_line2 : Text.t;
  status_line3 : Text.t;
  status_line4 : Text.t;
  status_line5 : Text.t;
  status_line6 : Text.t;
  status_line7 : Text.t;
  status_line8 : Text.t;
  status_line9 : Text.t;
}

type demo = {
  visuals : visuals;
  main_timeline : Timeline.t;
  sub_timeline1 : Timeline.t;
  sub_timeline2 : Timeline.t;
  mutable main_progress : Box.t option;
  mutable sub1_progress : Box.t option;
  mutable sub2_progress : Box.t option;
  live_lease : O.Renderer.live_lease;
  mutable pre_render : O.Renderer.pre_render_driver option;
  mutable key_subscription : O.Event_subscription.t option;
  mutable destroyed : bool;
}

let create_visuals renderer =
  let context = O.Renderer.context renderer in
  let parent = expect_ok (Box.create context ~id:"timeline-container" ()) in
  let parent_renderable = Box.as_renderable parent in
  ignore
    (expect_ok
       (O.Renderable.set_width parent_renderable (O.Yoga.Percent 100.0)));
  ignore
    (expect_ok
       (O.Renderable.set_height parent_renderable (O.Yoga.Percent 100.0)));
  ignore
    (expect_ok
       (O.Renderable.set_flex_shrink parent_renderable (Some 0.0)));
  ignore (expect_ok (O.Renderable.set_z_index parent_renderable 10));
  attach (O.Renderer.children renderer) parent_renderable;

  let box_object =
    add_bordered_box context parent ~id:"box-object" ~left:10.0 ~top:8.0
      ~width:8.0 ~height:4.0 ~background_color:(color "#FF6B6B")
      ~title:"Box" ~title_alignment:O.Lib.Border.Center ~z_index:1
  in
  let color_object =
    add_bordered_box context parent ~id:"color-object" ~left:25.0 ~top:8.0
      ~width:12.0 ~height:4.0 ~background_color:(color "#FF0000")
      ~title:"Color" ~title_alignment:O.Lib.Border.Center ~z_index:1
  in
  let physics_object =
    add_bordered_box context parent ~id:"physics-object" ~left:45.0 ~top:8.0
      ~width:12.0 ~height:4.0 ~background_color:(color "#4ECDC4")
      ~title:"Physics" ~title_alignment:O.Lib.Border.Center ~z_index:1
  in
  let alternating_object =
    add_bordered_box context parent ~id:"alternating-object" ~left:1.0
      ~top:1.0 ~width:8.0 ~height:4.0 ~background_color:(color "#9B59B6")
      ~title:"Alternate" ~title_alignment:O.Lib.Border.Center ~z_index:1
  in
  ignore
    (add_bordered_box context parent ~id:"main-timeline" ~left:2.0 ~top:15.0
       ~width:60.0 ~height:3.0 ~background_color:(color "#333366")
       ~title:"Main Timeline (20s)" ~title_alignment:O.Lib.Border.Left
       ~z_index:1);
  ignore
    (add_bordered_box context parent ~id:"sub-timeline-1" ~left:2.0
       ~top:19.0 ~width:30.0 ~height:3.0 ~background_color:(color "#333366")
       ~title:"Sub Timeline 1 (8s)" ~title_alignment:O.Lib.Border.Left
       ~z_index:1);
  ignore
    (add_bordered_box context parent ~id:"sub-timeline-2" ~left:35.0
       ~top:19.0 ~width:27.0 ~height:3.0 ~background_color:(color "#333366")
       ~title:"Sub Timeline 2 (6s)" ~title_alignment:O.Lib.Border.Left
       ~z_index:1);
  ignore
    (add_bordered_box context parent ~id:"status" ~left:2.0 ~top:24.0
       ~width:60.0 ~height:14.0 ~background_color:(color "#1a1a2e")
       ~title:"Animation Values" ~title_alignment:O.Lib.Border.Center
       ~z_index:1);

  let white = O.Color.white in
  let status_line1 =
    add_text context parent ~id:"status-line1" ~left:4.0 ~top:25.0
      ~foreground:white ~content:"Timeline: Initializing..." ~z_index:2
  in
  let status_line2 =
    add_text context parent ~id:"status-line2" ~left:4.0 ~top:26.0
      ~foreground:(color "#FFFF00") ~content:"Box Position: x=0.0, y=0.0"
      ~z_index:2
  in
  let status_line3 =
    add_text context parent ~id:"status-line3" ~left:4.0 ~top:27.0
      ~foreground:(color "#FFE66D")
      ~content:"Box Scale/Rot: scale=1.0, rot=0.0" ~z_index:2
  in
  let status_line4 =
    add_text context parent ~id:"status-line4" ~left:4.0 ~top:28.0
      ~foreground:(color "#FF6B6B") ~content:"Color: rgb(255, 0, 0)"
      ~z_index:2
  in
  let status_line5 =
    add_text context parent ~id:"status-line5" ~left:4.0 ~top:29.0
      ~foreground:(color "#FF9999") ~content:"Color Opacity: 1.0" ~z_index:2
  in
  let status_line6 =
    add_text context parent ~id:"status-line6" ~left:4.0 ~top:30.0
      ~foreground:(color "#4ECDC4")
      ~content:"Physics: v=0.0, a=0.0, m=1.0" ~z_index:2
  in
  let status_line7 =
    add_text context parent ~id:"status-line7" ~left:4.0 ~top:31.0
      ~foreground:(color "#CCCCCC")
      ~content:"Progress: Main=0% Sub1=0% Sub2=0%" ~z_index:2
  in
  let status_line8 =
    add_text context parent ~id:"status-line8" ~left:4.0 ~top:32.0
      ~foreground:(color "#FFE66D")
      ~content:"Example Value: 0.000 (0.0 → 0.5)" ~z_index:2
  in
  let status_line9 =
    add_text context parent ~id:"status-line9" ~left:4.0 ~top:33.0
      ~foreground:(color "#9B59B6")
      ~content:"Alternating: x=65 (left/right loop=5)" ~z_index:2
  in
  {
    renderer;
    parent;
    box_object;
    color_object;
    physics_object;
    alternating_object;
    status_line1;
    status_line2;
    status_line3;
    status_line4;
    status_line5;
    status_line6;
    status_line7;
    status_line8;
    status_line9;
  }

let setup_animations visuals ~main_timeline ~sub_timeline1 ~sub_timeline2 =
  let box_x = ref 0.0 in
  let box_y = ref 0.0 in
  let box_scale = ref 1.0 in
  let box_rotation = ref 0.0 in
  let color_red = ref 255.0 in
  let color_green = ref 0.0 in
  let color_blue = ref 0.0 in
  let color_opacity = ref 1.0 in
  let physics_velocity = ref 0.0 in
  let physics_acceleration = ref 0.0 in
  let physics_mass = ref 1.0 in
  let example_value = ref 0.0 in
  let alternating_x = ref 1.0 in
  let binding reference ~to_ = Property.bind_ref reference ~to_ in
  let update_box_position x y =
    set_box_position visuals.box_object
      ~x:(Int.max 1 (Int.min 70 (10 + javascript_round (x /. 3.0))))
      ~y:(Int.max 1 (Int.min 30 (8 + javascript_round (y /. 5.0))))
  in
  let update_box_size ~minimum_size ~minimum_height scale =
    let size = Int.max minimum_size (javascript_round (4.0 *. scale)) in
    set_box_width visuals.box_object size;
    set_box_height visuals.box_object
      (Int.max minimum_height (javascript_round (float_of_int size /. 2.0)))
  in
  ignore
    (expect_animation_ok
       (Timeline.add sub_timeline1
          ~bindings:[ binding box_x ~to_:100.0; binding box_y ~to_:50.0 ]
          ~duration_ms:2000.0 ~easing:Easing.in_out_quad
          ~on_update:(fun update ->
            ignore update;
            update_box_position !box_x !box_y;
            set_text visuals.status_line2 ~foreground:(color "#FFFF00")
              (Printf.sprintf "Box Position: x=%.1f, y=%.1f" !box_x !box_y))
          ())) ;
  ignore
    (expect_animation_ok
       (Timeline.add sub_timeline1
          ~bindings:[
            binding box_scale ~to_:2.0;
            binding box_rotation ~to_:Float.pi;
          ]
          ~start_time_ms:1000.0 ~duration_ms:1500.0
          ~easing:Easing.in_out_quad
          ~on_update:(fun update ->
            ignore update;
            update_box_size ~minimum_size:4 ~minimum_height:2 !box_scale;
            set_text visuals.status_line3 ~foreground:(color "#FFE66D")
              (Printf.sprintf "Box Scale/Rot: scale=%.2f, rot=%.2f" !box_scale
                 !box_rotation))
          ())) ;
  ignore
    (expect_animation_ok
       (Timeline.add sub_timeline1
          ~bindings:[
            binding box_x ~to_:(-50.0);
            binding box_y ~to_:(-25.0);
            binding box_scale ~to_:0.5;
            binding box_rotation ~to_:0.0;
          ]
          ~start_time_ms:4000.0 ~duration_ms:3000.0
          ~easing:Easing.in_out_sine
          ~on_update:(fun update ->
            ignore update;
            update_box_position !box_x !box_y;
            update_box_size ~minimum_size:2 ~minimum_height:1 !box_scale;
            set_text visuals.status_line2 ~foreground:(color "#FFFF00")
              (Printf.sprintf "Box Position (Reset): x=%.1f, y=%.1f" !box_x
                 !box_y);
            set_text visuals.status_line3 ~foreground:(color "#FFE66D")
              (Printf.sprintf "Box Scale/Rot (Reset): scale=%.2f, rot=%.2f"
                 !box_scale !box_rotation))
          ())) ;

  ignore
    (expect_animation_ok
       (Timeline.add sub_timeline2
          ~bindings:[
            binding color_red ~to_:0.0;
            binding color_green ~to_:255.0;
            binding color_blue ~to_:128.0;
          ]
          ~duration_ms:2000.0 ~easing:Easing.linear
          ~on_update:(fun update ->
            ignore update;
            let red = javascript_round !color_red in
            let green = javascript_round !color_green in
            let blue = javascript_round !color_blue in
            set_box_rgb visuals.color_object red green blue;
            set_text visuals.status_line4 ~foreground:(color "#FF6B6B")
              (Printf.sprintf "Color: rgb(%d, %d, %d)" red green blue))
          ())) ;
  ignore
    (expect_animation_ok
       (Timeline.add sub_timeline2 ~bindings:[ binding color_opacity ~to_:0.2 ]
          ~start_time_ms:1500.0 ~duration_ms:1000.0 ~easing:Easing.in_expo
          ~on_update:(fun update ->
            ignore update;
            set_text visuals.status_line5 ~foreground:(color "#FF9999")
              (Printf.sprintf "Color Opacity: %.2f" !color_opacity))
          ())) ;
  ignore
    (expect_animation_ok
       (Timeline.add sub_timeline2
          ~bindings:[
            binding color_red ~to_:255.0;
            binding color_green ~to_:255.0;
            binding color_blue ~to_:0.0;
            binding color_opacity ~to_:1.0;
          ]
          ~start_time_ms:3500.0 ~duration_ms:2500.0 ~easing:Easing.out_expo
          ~on_update:(fun update ->
            ignore update;
            let red = javascript_round !color_red in
            let green = javascript_round !color_green in
            let blue = javascript_round !color_blue in
            set_box_rgb visuals.color_object red green blue;
            set_text visuals.status_line4 ~foreground:(color "#FF6B6B")
              (Printf.sprintf "Final Color: rgb(%d, %d, %d), opacity=%.2f" red
                 green blue !color_opacity))
          ())) ;

  ignore
    (expect_animation_ok
       (Timeline.call main_timeline ~start_time_ms:0.0 (fun () ->
            set_text visuals.status_line1 ~foreground:O.Color.white
              "=== STARTING ANIMATION CYCLE ===")));
  ignore
    (expect_animation_ok
       (Timeline.add main_timeline
          ~bindings:[ binding example_value ~to_:0.5 ] ~duration_ms:10000.0
          ~easing:Easing.in_out_sine
          ~on_update:(fun update ->
            ignore update;
            set_text visuals.status_line8 ~foreground:(color "#FFE66D")
              (Printf.sprintf "Example Value: %.3f (0.0 → 0.5)" !example_value))
          ())) ;
  ignore
    (expect_animation_ok
       (Timeline.add main_timeline
          ~bindings:[ binding alternating_x ~to_:50.0 ]
          ~start_time_ms:1000.0 ~duration_ms:800.0
          ~easing:Easing.in_out_quad ~loops:(Timeline.Count 5)
          ~alternate:true ~loop_delay_ms:200.0
          ~on_update:(fun update ->
            ignore update;
            set_box_position visuals.alternating_object
              ~x:(javascript_round !alternating_x) ~y:1;
            set_text visuals.status_line9 ~foreground:(color "#9B59B6")
              (Printf.sprintf "Alternating: x=%.1f (left/right loop=5)"
                 !alternating_x))
          ())) ;
  ignore
    (expect_animation_ok
       (Timeline.add main_timeline
          ~bindings:[
            binding physics_velocity ~to_:50.0;
            binding physics_acceleration ~to_:9.8;
            binding physics_mass ~to_:2.5;
          ]
          ~start_time_ms:1000.0 ~duration_ms:4000.0
          ~easing:Easing.in_out_sine
          ~on_update:(fun update ->
            ignore update;
            let velocity_height =
              Int.max 1 (javascript_round (!physics_velocity /. 6.0))
            in
            set_box_height visuals.physics_object (Int.min 6 velocity_height);
            set_text visuals.status_line6 ~foreground:(color "#4ECDC4")
              (Printf.sprintf "Physics: v=%.1f, a=%.1f, m=%.1f"
                 !physics_velocity !physics_acceleration !physics_mass))
          ())) ;
  ignore
    (expect_animation_ok
       (Timeline.add main_timeline
          ~bindings:[
            binding physics_velocity ~to_:(-20.0);
            binding physics_acceleration ~to_:(-5.0);
            binding physics_mass ~to_:0.8;
          ]
          ~start_time_ms:8000.0 ~duration_ms:3000.0
          ~easing:Easing.in_out_sine
          ~on_update:(fun update ->
            ignore update;
            let velocity_height =
              Int.max 1
                (abs (javascript_round (!physics_velocity /. 4.0)))
            in
            set_box_height visuals.physics_object (Int.min 6 velocity_height);
            set_text visuals.status_line6 ~foreground:(color "#4ECDC4")
              (Printf.sprintf "Physics Reverse: v=%.1f, a=%.1f, m=%.1f"
                 !physics_velocity !physics_acceleration !physics_mass))
          ())) ;
  ignore
    (expect_animation_ok
       (Timeline.call main_timeline ~start_time_ms:9000.0 (fun () ->
            set_text visuals.status_line1 ~foreground:O.Color.white
              "=== CYCLE COMPLETE ===")))

let progress_width timeline maximum =
  let progress =
    Timeline.current_time_ms timeline /. Timeline.duration_ms timeline
  in
  Int.max 1 (int_of_float (Float.floor (progress *. float_of_int maximum)))

let progress_percent timeline =
  let progress =
    Timeline.current_time_ms timeline /. Timeline.duration_ms timeline
  in
  int_of_float (Float.floor (progress *. 100.0))

let ensure_progress_box demo ~timeline ~get ~set ~id ~left ~top ~maximum
    ~background_color =
  let width = progress_width timeline maximum in
  match get () with
  | Some box ->
      set_box_width box width;
      box
  | None ->
      let box =
        add_plain_box (O.Renderer.context demo.visuals.renderer)
          demo.visuals.parent ~id ~left ~top ~width:(float_of_int width)
          ~height:1.0 ~background_color ~z_index:2
      in
      set (Some box);
      box

let update_visuals demo =
  ignore
    (ensure_progress_box demo ~timeline:demo.main_timeline
       ~get:(fun () -> demo.main_progress)
       ~set:(fun value -> demo.main_progress <- value) ~id:"main-progress"
       ~left:3.0 ~top:16.0 ~maximum:58 ~background_color:(color "#FFE66D"));
  ignore
    (ensure_progress_box demo ~timeline:demo.sub_timeline1
       ~get:(fun () -> demo.sub1_progress)
       ~set:(fun value -> demo.sub1_progress <- value) ~id:"sub1-progress"
       ~left:3.0 ~top:20.0 ~maximum:28 ~background_color:(color "#FF6B6B"));
  ignore
    (ensure_progress_box demo ~timeline:demo.sub_timeline2
       ~get:(fun () -> demo.sub2_progress)
       ~set:(fun value -> demo.sub2_progress <- value) ~id:"sub2-progress"
       ~left:36.0 ~top:20.0 ~maximum:25 ~background_color:(color "#4ECDC4"));
  set_text demo.visuals.status_line7 ~foreground:(color "#CCCCCC")
    (Printf.sprintf "Progress: Main=%d%% Sub1=%d%% Sub2=%d%%"
       (progress_percent demo.main_timeline)
       (progress_percent demo.sub_timeline1)
       (progress_percent demo.sub_timeline2))

let update demo delta_seconds =
  expect_animation_update
    (Timeline.update demo.main_timeline ~delta_time_ms:(delta_seconds *. 1000.0));
  update_visuals demo

let start demo =
  set_text demo.visuals.status_line1 ~foreground:O.Color.white
    "Starting nested timeline example...";
  ignore (expect_animation_ok (Timeline.play demo.main_timeline))

let pause demo = ignore (expect_animation_ok (Timeline.pause demo.main_timeline))

let destroy demo =
  if not demo.destroyed then begin
    demo.destroyed <- true;
    Option.iter O.Event_subscription.cancel demo.key_subscription;
    Option.iter O.Renderer.detach_pre_render demo.pre_render;
    ignore (Timeline.pause demo.main_timeline);
    O.Renderer.release_live_lease demo.live_lease;
    ignore
      (expect_ok
         (O.Layout_children.remove (O.Renderer.children demo.visuals.renderer)
            (Box.as_renderable demo.visuals.parent)));
    Box.destroy_recursively demo.visuals.parent;
    demo.key_subscription <- None;
    demo.pre_render <- None
  end

let handle_key demo key_event =
  if Handler.key_event_kind key_event = Handler.Keypress then begin
    let modifiers = Handler.key_modifiers key_event in
    if not modifiers.ctrl && not modifiers.meta then
      match Handler.key key_event with
      | Key.Character bytes ->
          let value = String.lowercase_ascii (Bytes.to_string bytes) in
          if String.equal value "p" then pause demo
          else if String.equal value "r" then start demo
      | Key.Named _ -> ()
  end

let create_demo renderer =
  let visuals = create_visuals renderer in
  let main_timeline =
    expect_animation_ok (Timeline.create ~duration_ms:10000.0 ~loop:true ())
  in
  let sub_timeline1 =
    expect_animation_ok
      (Timeline.create ~duration_ms:8000.0 ~autoplay:false ())
  in
  let sub_timeline2 =
    expect_animation_ok
      (Timeline.create ~duration_ms:6000.0 ~autoplay:false ())
  in
  setup_animations visuals ~main_timeline ~sub_timeline1 ~sub_timeline2;
  ignore (expect_animation_ok (Timeline.sync main_timeline sub_timeline1 ()));
  ignore
    (expect_animation_ok
       (Timeline.sync main_timeline sub_timeline2 ~start_time_ms:3000.0 ()));
  let live_lease = expect_ok (O.Renderer.acquire_live_lease renderer) in
  {
    visuals;
    main_timeline;
    sub_timeline1;
    sub_timeline2;
    main_progress = None;
    sub1_progress = None;
    sub2_progress = None;
    live_lease;
    pre_render = None;
    key_subscription = None;
    destroyed = false;
  }

let run renderer ~exit ~copy_to_clipboard =
  ignore copy_to_clipboard;
  ignore
    (expect_ok
       (O.Renderer.set_background_color renderer ~color:(color "#000028")));
  let demo = create_demo renderer in
  let key_subscription =
    expect_ok (O.Renderer.on_keypress renderer (handle_key demo))
  in
  demo.key_subscription <- Some key_subscription;
  let pre_render =
    expect_ok
      (O.Renderer.attach_pre_render renderer (fun delta_seconds ->
           if not demo.destroyed then update demo delta_seconds))
  in
  demo.pre_render <- Some pre_render;
  ignore
    (expect_ok
       (O.Renderer.attach_before_destroy renderer (fun () -> destroy demo)));
  start demo

let () =
  Eio_main.run @@ fun env ->
  Opentui_examples_lib.App.run env ~target_frames_per_second:60
    ~init:(fun ~exit ~copy_to_clipboard renderer ->
      run renderer ~exit ~copy_to_clipboard;
      Opentui_examples_lib.Standalone_keys.setup_common_demo_keys renderer
        ~on_ctrl_c:exit)
