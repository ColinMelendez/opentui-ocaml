open Windtrap

module Three = Opentui_three.Three
module O3 = Three.Object3d
module V3 = Three.Vector3
module Facade = Opentui_three.Three_cli_renderer
module Core = Opentui_core

let expect_ok what result =
  match result with
  | Ok value -> value
  | Error error -> fail (what ^ ": " ^ Facade.Error.message error)

let expect_error what result =
  match result with
  | Error _ -> ()
  | Ok _ -> fail (what ^ ": unexpectedly succeeded")

let core_ok what result =
  match result with
  | Ok value -> value
  | Error error -> fail (what ^ ": " ^ Core.Error.message error)

let take_facade what result =
  match result with
  | Ok facade -> facade
  | Error error ->
      let message =
        "no usable WebGPU device for " ^ what ^ ": "
        ^ Facade.Error.message error
      in
      if Sys.getenv_opt "OPENTUI_WGPU_REQUIRE_DEVICE" = Some "1" then
        fail message
      else skip ~reason:message ()

let same_mode a b =
  match (a, b) with
  | `None, `None | `Cpu, `Cpu | `Gpu, `Gpu -> true
  | _ -> false

let projection_aspect facade =
  (* Column-major perspective: m[0] = focal / aspect, m[5] = focal, so the
     ratio recovers the aspect construction baked in. *)
  let m = O3.projection_matrix (Facade.active_camera facade) in
  Float.Array.get m 5 /. Float.Array.get m 0

let make_scene () =
  let root = Three.Scene.create () in
  let cube =
    Three.Mesh.create (Three.Box_geometry.create ())
      (Three.Mesh_lambert_material.create
         ~color:(Three.Color.create ~r:0.5 ~g:0.5 ~b:0.5 ())
         ())
  in
  O3.add root cube;
  let ambient = Three.Ambient_light.create ~intensity:0.25 () in
  let directional = Three.Directional_light.create ~intensity:1.0 () in
  V3.set (O3.position directional) 0.0 0.0 5.0;
  O3.add root ambient;
  O3.add root directional;
  root

let snapshots_equal (chars_a, fore_a, back_a, attrs_a)
    (chars_b, fore_b, back_b, attrs_b) =
  Array.for_all2 Int32.equal chars_a chars_b
  && Array.for_all2 Int32.equal fore_a fore_b
  && Array.for_all2 Int32.equal back_a back_b
  && Array.for_all2 Int32.equal attrs_a attrs_a

(* Counts cells whose glyph falls in the quadrant/block family and the
   distinct foreground words among them - structure, not exact RGB. *)
let survey buffer =
  let chars, fore, _back, _attrs =
    core_ok "snapshot" (Core.Owned_buffer.snapshot buffer)
  in
  let blocks = ref 0 in
  let colors = Hashtbl.create 8 in
  Array.iteri
    (fun i ch ->
      let code = Int32.to_int ch land 0xffff in
      let blockish =
        code = 0x2588 || code = 0x2580 || code = 0x2584 || code = 0x258C
        || code = 0x2590 || (code >= 0x2596 && code <= 0x259F)
      in
      if blockish then begin
        blocks := !blocks + 1;
        Hashtbl.replace colors fore.(i) ()
      end)
    chars;
  (!blocks, Hashtbl.length colors)

let () =
  run "opentui-three-cli-renderer"
    [
      test "aspect defaults to width over twice height" (fun () ->
          let facade = expect_ok "create" (Facade.create ~width:40 ~height:10 ()) in
          if Float.abs (projection_aspect facade -. 2.0) > 1e-9 then
            fail "default cell aspect should be 40 / (10 * 2) = 2";
          Facade.destroy facade);

      test "CELL_ASPECT_RATIO overrides the terminal default" (fun () ->
          Unix.putenv "CELL_ASPECT_RATIO" "1.75";
          let facade = expect_ok "create" (Facade.create ~width:40 ~height:10 ()) in
          Unix.putenv "CELL_ASPECT_RATIO" "";
          if Float.abs (projection_aspect facade -. 1.75) > 1e-9 then
            fail "env override did not reach the projection";
          Facade.destroy facade);

      test "explicit cell aspect wins over the environment" (fun () ->
          Unix.putenv "CELL_ASPECT_RATIO" "1.75";
          let facade =
            expect_ok "create"
              (Facade.create ~cell_aspect_ratio:0.5 ~width:40 ~height:10 ())
          in
          Unix.putenv "CELL_ASPECT_RATIO" "";
          if Float.abs (projection_aspect facade -. 0.5) > 1e-9 then
            fail "explicit aspect was not honored";
          Facade.destroy facade);

      test "focal length derives fov from cell rows like the reference"
        (fun () ->
          let facade =
            expect_ok "create"
              (Facade.create ~focal_length:8.0 ~width:40 ~height:20 ())
          in
          let expected_fov =
            (2.0 *. Float.atan (20.0 /. 16.0)) *. (180.0 /. Float.pi)
          in
          if
            Float.abs
              (Three.Perspective_camera.fov_degrees (Facade.active_camera facade)
              -. expected_fov)
            > 1e-9
          then fail "focal-length fov formula diverged from the reference";
          Facade.destroy facade);

      test "lifecycle guards draw before init and after destroy" (fun () ->
          let facade = expect_ok "create" (Facade.create ~width:8 ~height:4 ()) in
          let buffer =
            core_ok "buffer" (Core.Owned_buffer.create ~width:8 ~height:4 ())
          in
          let scene = make_scene () in
          (* Reference parity: drawing before init silently no-ops. *)
          expect_ok "draw before init"
            (Facade.draw_scene facade ~root:scene ~buffer ~delta_time:0.0);
          expect_ok "init" (Facade.init facade);
          expect_error "second init" (Facade.init facade);
          Facade.destroy facade;
          Facade.destroy facade;
          expect_ok "draw after destroy no-ops"
            (Facade.draw_scene facade ~root:scene ~buffer ~delta_time:0.0);
          Core.Owned_buffer.close buffer);

      test "super-sample toggle cycles none, cpu, gpu" (fun () ->
          let facade = expect_ok "create" (Facade.create ~width:8 ~height:4 ()) in
          if not (same_mode (Facade.get_super_sample facade) `Gpu) then
            fail "default super sampling should be gpu";
          List.iter
            (fun expected ->
              expect_ok "toggle" (Facade.toggle_super_sampling facade);
              if not (same_mode (Facade.get_super_sample facade) expected) then
                fail "toggle order diverged from the reference cycle")
            [ `None; `Cpu; `Gpu ];
          Facade.destroy facade);

      test "set_size rescales render dimensions and camera aspect" (fun () ->
          let facade =
            take_facade "the resize check" (Facade.create ~width:16 ~height:8 ())
          in
          expect_ok "init" (Facade.init facade);
          expect_ok "resize" (Facade.set_size facade ~width:32 ~height:8);
          if Float.abs (projection_aspect facade -. 2.0) > 1e-9 then
            fail "resize did not refresh the camera aspect to 32/(8*2)";
          Facade.destroy facade);

      test "save_to_file emits a decodable PNG of the staged frame"
        (fun () ->
          let blue =
            match Core.Color.rgba ~red:0 ~green:0 ~blue:255 ~alpha:255 with
            | Ok color -> color
            | Error e -> fail ("color: " ^ Core.Native.Error.message e)
          in
          let facade =
            take_facade "the save check"
              (Facade.create ~super_sample:`Cpu ~background_color:blue
                 ~focal_length:0.75 ~width:8 ~height:4 ())
          in
          expect_ok "init" (Facade.init facade);
          let root = make_scene () in
          let buffer =
            core_ok "buffer" (Core.Owned_buffer.create ~width:8 ~height:4 ())
          in
          expect_ok "draw"
            (Facade.draw_scene facade ~root ~buffer ~delta_time:0.016);
          let path =
            Filename.concat (Filename.get_temp_dir_name ())
              ("otui-three-save-" ^ string_of_int (Unix.getpid ()) ^ ".png")
          in
          expect_ok "save" (Facade.save_to_file facade ~path);
          let encoded =
            let channel = open_in_bin path in
            Fun.protect
              (fun () ->
                let length = in_channel_length channel in
                really_input_string channel length)
              ~finally:(fun () -> close_in channel)
          in
          Sys.remove path;
          (* Structural verification: core's native decoder accepts our
             emission at the render dimensions with the clear color's blue
             channel present somewhere in the corner region. *)
          let image =
            match Core.Image.decode (Bytes.of_string encoded) with
            | Ok image -> image
            | Error error ->
                fail ("decode: " ^ Core.Image.decode_message error)
          in
          (* Cpu mode renders at 2x output; saves use render dimensions. *)
          (match Core.Image.width image with
          | Ok w when Int.equal w 16 -> ()
          | Ok w -> fail (Printf.sprintf "png width %d, expected 16" w)
          | Error e -> fail ("width: " ^ Core.Image.message e));
          (match Core.Image.height image with
          | Ok h when Int.equal h 8 -> ()
          | Ok h -> fail (Printf.sprintf "png height %d, expected 8" h)
          | Error e -> fail ("height: " ^ Core.Image.message e));
          let decoded, _stride =
            match Core.Image.copy image () with
            | Ok (bytes, stride) -> (bytes, stride)
            | Error e -> fail ("copy: " ^ Core.Image.message e)
          in
          (* Corner pixel is the blue clear color in raw linear bytes. *)
          if not (Int.equal (Char.code (Bytes.get decoded 2)) 255) then begin
            let prefix = Bytes.sub_string decoded 0 32 in
            fail
              (Printf.sprintf "corner blue got %d; prefix=%s"
                 (Char.code (Bytes.get decoded 2))
                 (String.escaped prefix))
          end;
          Core.Image.close image;
          Core.Owned_buffer.close buffer;
          Facade.destroy facade);

      test "sample algorithm accessors round trip" (fun () ->
          let facade = expect_ok "create" (Facade.create ~width:8 ~height:4 ()) in
          if
            (match Facade.get_super_sample_algorithm facade with
            | `Standard -> true
            | _ -> false)
            |> not
          then fail "default algorithm should be standard";
          expect_ok "set pre-squeezed"
            (Facade.set_super_sample_algorithm facade `Pre_squeezed);
          if
            (match Facade.get_super_sample_algorithm facade with
            | `Pre_squeezed -> true
            | _ -> false)
            |> not
          then fail "algorithm setter did not stick";
          Facade.destroy facade);

      test "memory renderer shows cube structure deterministically" (fun () ->
          let core_renderer =
            core_ok "memory renderer"
              (Core.Renderer.create ~output:Core.Renderer.Output.Memory
                 ~width:24l ~height:12l ())
          in
          let frame =
            core_ok "frame buffer"
              (Core.Renderables.Frame_buffer.create
                 (Core.Renderer.context core_renderer)
                 ~respect_alpha:true ~width:24 ~height:12 ())
          in
          ignore
            (core_ok "attach"
               (Core.Layout_children.add (Core.Renderer.children core_renderer)
                  (Core.Renderables.Frame_buffer.as_renderable frame)));
          let buffer = Core.Renderables.Frame_buffer.frame_buffer frame in
          let facade =
            take_facade "the snapshot suite"
              (Facade.create ~super_sample:`Cpu ~width:24 ~height:12 ())
          in
          expect_ok "init" (Facade.init facade);
          let scene = make_scene () in
          let clear_and_draw () =
            core_ok "clear"
              (Core.Owned_buffer.clear buffer ~background:Core.Color.transparent);
            expect_ok "draw"
              (Facade.draw_scene facade ~root:scene ~buffer ~delta_time:0.016)
          in
          clear_and_draw ();
          let blocks, shades = survey buffer in
          if blocks < 12 then
            fail
              (Printf.sprintf
                 "only %d block-family cells rendered; silhouette missing" blocks);
          if shades < 2 then fail "expected at least two foreground shades";
          clear_and_draw ();
          let first = core_ok "snap one" (Core.Owned_buffer.snapshot buffer) in
          clear_and_draw ();
          let second = core_ok "snap two" (Core.Owned_buffer.snapshot buffer) in
          if not (snapshots_equal first second) then
            fail "two identical renders produced different cells";
          Core.Renderables.Frame_buffer.destroy frame;
          Facade.destroy facade;
          Core.Renderer.close core_renderer |> ignore);
    ]
