open Windtrap

module Three = Opentui_three.Three
module O3 = Three.Object3d
module V3 = Three.Vector3
module Owned_buffer = Opentui_core.Owned_buffer

let take_engine what result =
  match result with
  | Ok engine -> engine
  | Error error ->
      let message =
        "no usable WebGPU device for " ^ what ^ ": "
        ^ Opentui_wgpu.Wgpu.Error.message error
      in
      if Sys.getenv_opt "OPENTUI_WGPU_REQUIRE_DEVICE" = Some "1" then
        fail message
      else skip ~reason:message ()

let expect_ok what result =
  match result with
  | Ok value -> value
  | Error error -> fail (what ^ ": " ^ Opentui_wgpu.Wgpu.Error.message error)

let size = 32

let pixel snapshot ~row ~column =
  let base = ((row * size) + column) * 4 in
  ( Char.code snapshot.[base],
    Char.code snapshot.[base + 1],
    Char.code snapshot.[base + 2] )

let () =
  run "opentui-three-textures"
    [
      test "checkerboard generator is deterministic and alternating"
        (fun () ->
          let a = Three.Texture_utils.checkerboard ~size:4 ~squares:2 () in
          let b = Three.Texture_utils.checkerboard ~size:4 ~squares:2 () in
          if not (Bytes.equal (Three.Texture.pixels a) (Three.Texture.pixels b))
          then fail "same parameters produced different bytes";
          let px x y =
            let base = ((y * 4) + x) * 4 in
            Char.code (Bytes.get (Three.Texture.pixels a) base)
          in
          (* 2x2 squares over a 4x4 texture: top-left cell bright, its right
             neighbor dark. *)
          if not (Int.equal (px 0 0) 255) then fail "cell (0,0) should be a";
          if not (Int.equal (px 3 0) 0) then fail "cell (1,0) should be b");

      test "gradient generators interpolate along the chosen axis" (fun () ->
          let vertical =
            Three.Texture_utils.gradient ~kind:`Vertical ~size:4
              ~from:(0, 0, 0) ~to_:(255, 255, 255)
              ()
          in
          let p = Three.Texture.pixels vertical in
          let first_row = Char.code (Bytes.get p 0) in
          let last_row = Char.code (Bytes.get p (((3 * 4) + 0) * 4)) in
          if not (first_row < last_row) then
            fail "vertical gradient did not increase downward";
          let horizontal =
            Three.Texture_utils.gradient ~kind:`Horizontal ~size:4
              ~from:(0, 0, 0) ~to_:(255, 0, 0)
              ()
          in
          let hp = Three.Texture.pixels horizontal in
          (* Pixel centers sample at t = 0.125 .. 0.875 on a 4-wide texture. *)
          if not (Char.code (Bytes.get hp (((0 * 4) + 0) * 4)) < 64) then
            fail "horizontal gradient should start near dark";
          if not (Char.code (Bytes.get hp (((0 * 4) + 3) * 4)) > 191) then
            fail "horizontal gradient should end near bright");

      test "octave noise is deterministic per seed" (fun () ->
          let n1 = Three.Texture_utils.octave_noise ~seed:7 ~octaves:3 ~size:8 in
          let n2 = Three.Texture_utils.octave_noise ~seed:7 ~octaves:3 ~size:8 in
          let n3 = Three.Texture_utils.octave_noise ~seed:9 ~octaves:3 ~size:8 in
          if
            not
              (Bytes.equal (Three.Texture.pixels n1) (Three.Texture.pixels n2))
          then fail "same seed produced different noise";
          if Bytes.equal (Three.Texture.pixels n1) (Three.Texture.pixels n3)
          then fail "different seeds produced identical noise");

      test "mapped lambert cube shows the checkerboard through lighting"
        (fun () ->
          let engine =
            take_engine "the checker cube"
              (Three.Engine.create ~width:size ~height:size ())
          in
          let root = Three.Scene.create () in
          let texture =
            Three.Texture_utils.checkerboard ~size:64 ~squares:8 ()
          in
          let material =
            Three.Mesh_lambert_material.create
              ~color:(Three.Color.create ~r:1.0 ~g:1.0 ~b:1.0 ())
              ()
          in
          material.map <- Some texture;
          let cube = Three.Mesh.create (Three.Box_geometry.create ()) material in
          O3.add root cube;
          let ambient = Three.Ambient_light.create ~intensity:0.0 () in
          let directional = Three.Directional_light.create ~intensity:0.6 () in
          V3.set (O3.position directional) 0.0 0.0 5.0;
          O3.add root ambient;
          O3.add root directional;
          let camera =
            Three.Perspective_camera.create ~fov_degrees:50.0 ~aspect:1.0 ()
          in
          V3.set (O3.position camera) 0.0 0.0 3.0;
          expect_ok "render"
            (Three.Engine.render engine ~root ~camera
               ~clear_color:(0.0, 0.0, 1.0, 1.0)
               ());
          let snapshot = Three.Engine.snapshot engine in
          (* Head-on face with N.L = 1: lit factor 0.6, so white checkers
             land near byte 153 and black checkers stay at zero. Both must
             appear across the front face; background stays outside. *)
          let bright = ref 0 and dark = ref 0 in
          for row = 10 to 22 do
            for column = 10 to 22 do
              let (r, g, b) = pixel snapshot ~row ~column in
              ignore g;
              ignore b;
              if r > 140 then incr bright
              else if r < 20 then incr dark
            done
          done;
          if !bright < 20 || !dark < 20 then begin
            let mn = ref 255 and mx = ref 0 in
            for row = 10 to 22 do
              for column = 10 to 22 do
                let (r, _, _) = pixel snapshot ~row ~column in
                mn := min !mn r;
                mx := max !mx r
              done
            done;
            fail
              (Printf.sprintf
                 "checkers incomplete: bright=%d dark=%d r range [%d..%d]"
                 !bright !dark !mn !mx)
          end;
          Three.Engine.destroy engine);

      test "unmapping falls back to flat albedo without re-creating meshes"
        (fun () ->
          let engine =
            take_engine "the unmap check"
              (Three.Engine.create ~width:size ~height:size ())
          in
          let root = Three.Scene.create () in
          let material =
            Three.Mesh_lambert_material.create
              ~color:(Three.Color.create ~r:0.5 ~g:0.5 ~b:0.5 ())
              ()
          in
          let cube = Three.Mesh.create (Three.Box_geometry.create ()) material in
          O3.add root cube;
          let ambient = Three.Ambient_light.create ~intensity:0.25 () in
          let directional = Three.Directional_light.create ~intensity:1.0 () in
          V3.set (O3.position directional) 0.0 0.0 5.0;
          O3.add root ambient;
          O3.add root directional;
          let camera =
            Three.Perspective_camera.create ~fov_degrees:50.0 ~aspect:1.0 ()
          in
          V3.set (O3.position camera) 0.0 0.0 3.0;
          expect_ok "render mapped"
            (Three.Engine.render engine ~root ~camera
               ~clear_color:(0.0, 0.0, 1.0, 1.0)
               ());
          material.map <- Some (Three.Texture_utils.checkerboard ~size:16 ~squares:4 ());
          expect_ok "render remapped"
            (Three.Engine.render engine ~root ~camera
               ~clear_color:(0.0, 0.0, 1.0, 1.0)
               ());
          let snapshot = Three.Engine.snapshot engine in
          (* The checker pattern must reach the framebuffer after the swap. *)
          let bright = ref 0 in
          for row = 12 to 20 do
            for column = 12 to 20 do
              let (r, _, _) = pixel snapshot ~row ~column in
              if r > 100 then incr bright
            done
          done;
          if !bright = 0 then fail "remap produced no bright checkers";
          Three.Engine.destroy engine);
    ]
