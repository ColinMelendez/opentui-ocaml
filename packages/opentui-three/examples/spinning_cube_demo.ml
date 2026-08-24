(* Phase 1 acceptance demo: a rotating lambert cube rendered through the
   three CLI facade into a framebuffer renderable, ported from the
   reference three-renderer demos' shape (scene assembly, per-frame euler
   mutation, live lease, standalone exit keys). Keys: s toggles super
   sampling, ctrl-c exits. *)

module O = Opentui_core
module Three = Opentui_three.Three
module Facade = Opentui_three.Three_cli_renderer
module Frame_buffer = O.Renderables.Frame_buffer
module Owned_buffer = O.Owned_buffer
module Handler = O.Lib.Key_handler
module Key = O.Lib.Key_decoder

let expect_ok result =
  match result with Ok value -> value | Error error -> invalid_arg (O.Error.message error)

let expect_facade what result =
  match result with
  | Ok value -> value
  | Error error -> invalid_arg ("three: " ^ Facade.Error.message error)

let label_foreground =
  match O.Color.rgba ~red:200 ~green:200 ~blue:220 ~alpha:255 with
  | Ok color -> color
  | Error _ -> O.Color.white

type demo = {
  renderer : O.Renderer.t;
  frame : Frame_buffer.t;
  buffer : Owned_buffer.t;
  facade : Facade.t;
  root : Three.Object3d.t;
  cube : Three.Object3d.t;
  live_lease : O.Renderer.live_lease;
  mutable key_subscription : O.Event_subscription.t option;
  mutable resize_subscription : O.Event_subscription.t option;
  mutable pre_render : O.Renderer.pre_render_driver option;
  mutable destroyed : bool;
}

let render_demo demo ~delta =
  if not demo.destroyed then begin
    (* The caller owns clearing; reference demos clear transparent each
       frame so cells composite onto the terminal like respectAlpha. *)
    ignore (Owned_buffer.clear demo.buffer ~background:O.Color.transparent);
    demo.cube.rotation.y <- demo.cube.rotation.y +. (delta *. 0.9);
    demo.cube.rotation.x <- demo.cube.rotation.x +. (delta *. 0.55);
    ignore
      (expect_facade "draw_scene"
         (Facade.draw_scene demo.facade ~root:demo.root ~buffer:demo.buffer
            ~delta_time:delta));
    ignore
      (Owned_buffer.draw_text demo.buffer ~text:"three: spinning cube (s: supersample)"
         ~x:2 ~y:0 ~foreground:label_foreground
         ~background:O.Color.transparent ~attributes:0l)
  end

let request_frame demo =
  ignore (expect_ok (O.Renderer.request_render demo.renderer))

let handle_key demo key_event =
  if Handler.key_event_kind key_event = Handler.Keypress then begin
    let modifiers = Handler.key_modifiers key_event in
    if not modifiers.ctrl && not modifiers.meta then
      match Handler.key key_event with
      | Key.Character bytes when String.equal (Bytes.to_string bytes) "s" ->
          ignore (Facade.toggle_super_sampling demo.facade);
          request_frame demo
      | Key.Named _ | Key.Character _ -> ()
  end

let destroy demo =
  if not demo.destroyed then begin
    demo.destroyed <- true;
    Option.iter O.Event_subscription.cancel demo.key_subscription;
    Option.iter O.Event_subscription.cancel demo.resize_subscription;
    Option.iter O.Renderer.detach_pre_render demo.pre_render;
    O.Renderer.release_live_lease demo.live_lease;
    let removal =
      O.Layout_children.remove (O.Renderer.children demo.renderer)
        (Frame_buffer.as_renderable demo.frame)
    in
    ignore removal;
    Frame_buffer.destroy demo.frame;
    Facade.destroy demo.facade;
    demo.key_subscription <- None;
    demo.resize_subscription <- None;
    demo.pre_render <- None
  end

let run renderer =
  let width = Int32.to_int (expect_ok (O.Renderer.terminal_width renderer)) in
  let height = Int32.to_int (expect_ok (O.Renderer.terminal_height renderer)) in
  let frame =
    expect_ok
      (Frame_buffer.create (O.Renderer.context renderer) ~id:"three-cube"
         ~respect_alpha:true ~width ~height ())
  in
  ignore
    (expect_ok
       (O.Layout_children.add (O.Renderer.children renderer)
          (Frame_buffer.as_renderable frame)));
  let facade =
    expect_facade "create"
      (Facade.create ~focal_length:12.0 ~super_sample:`Cpu ~width ~height ())
  in
  expect_facade "init" (Facade.init facade);
  let root = Three.Scene.create () in
  let cube =
    Three.Mesh.create (Three.Box_geometry.create ())
      (Three.Mesh_lambert_material.create
         ~color:(Three.Color.from_hex_int 0xff8844)
         ())
  in
  Three.Object3d.set_name cube (Some "cube");
  Three.Object3d.add root cube;
  Three.Object3d.add root (Three.Ambient_light.create ~intensity:0.3 ());
  let sun = Three.Directional_light.create ~intensity:1.1 () in
  Three.Vector3.set (Three.Object3d.position sun) 2.5 3.0 4.0;
  Three.Object3d.add root sun;
  let live_lease = expect_ok (O.Renderer.acquire_live_lease renderer) in
  let buffer = Frame_buffer.frame_buffer frame in
  let demo =
    { renderer;
      frame;
      buffer;
      facade;
      root;
      cube;
      live_lease;
      key_subscription = None;
      resize_subscription = None;
      pre_render = None;
      destroyed = false }
  in
  demo.key_subscription <-
    Some (expect_ok (O.Renderer.on_keypress renderer (handle_key demo)));
  demo.resize_subscription <-
    Some
      (expect_ok
         (O.Renderer.on_resize renderer (fun { O.Renderer.width; height } ->
              let width = Int32.to_int width and height = Int32.to_int height in
              ignore (Frame_buffer.resize demo.frame ~width ~height);
              ignore (Facade.set_size demo.facade ~width ~height))));
  demo.pre_render <-
    Some
      (expect_ok
         (O.Renderer.attach_pre_render renderer (fun delta ->
              render_demo demo ~delta)));
  ignore
    (expect_ok (O.Renderer.attach_before_destroy renderer (fun () -> destroy demo)))

let () =
  Eio_main.run @@ fun env ->
  Opentui_examples_lib.App.run env ~target_frames_per_second:30
    ~init:(fun ~exit ~copy_to_clipboard renderer ->
      ignore copy_to_clipboard;
      run renderer;
      Opentui_examples_lib.Standalone_keys.setup_common_demo_keys renderer
        ~on_ctrl_c:exit)
