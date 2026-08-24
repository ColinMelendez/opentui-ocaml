open Windtrap

module Three = Opentui_three.Three
module O3 = Three.Object3d
module V3 = Three.Vector3

module Wgpu_error = Opentui_wgpu.Wgpu.Error

let take_engine ?(enforce_via_skip = true) what result =
  match result with
  | Ok engine -> engine
  | Error error ->
      let message =
        "no usable WebGPU device for " ^ what ^ ": "
        ^ Wgpu_error.message error
      in
      if Sys.getenv_opt "OPENTUI_WGPU_REQUIRE_DEVICE" = Some "1" then
        fail message
      else if enforce_via_skip then skip ~reason:message ()
      else fail message

let expect_render result =
  match result with
  | Ok () -> ()
  | Error error -> fail ("render: " ^ Wgpu_error.message error)

let size = 32

let background = (0, 0, 255)

let pixel snapshot ~width ~row ~column =
  let base = ((row * width) + column) * 4 in
  ( Char.code snapshot.[base],
    Char.code snapshot.[base + 1],
    Char.code snapshot.[base + 2] )

let rgb_equal (a, b, c) (d, e, f) =
  Int.equal a d && Int.equal b e && Int.equal c f

let expect_pixel ?(tolerance = 2) snapshot ~width ~row ~column
    ~(expected : int * int * int) =
  let er, eg, eb = expected in
  let ar, ag, ab = pixel snapshot ~width ~row ~column in
  if
    Int.abs (ar - er) > tolerance
    || Int.abs (ag - eg) > tolerance
    || Int.abs (ab - eb) > tolerance
  then
    fail
      (Printf.sprintf
         "pixel (%d,%d): got rgb(%d,%d,%d) expected rgb(%d,%d,%d) (+/-%d)"
         row column ar ag ab er eg eb tolerance)

let camera_at ?(z = 3.0) () =
  let camera = Three.Perspective_camera.create ~fov_degrees:50.0 ~aspect:1.0 () in
  V3.set (O3.position camera) 0.0 0.0 z;
  camera

let run_frame engine ~root ~camera =
  expect_render
    (Three.Engine.render engine ~root ~camera ~clear_color:(0.0, 0.0, 1.0, 1.0) ())

let () =
  run "opentui-three-phong"
    [
      test "phong adds a centered specular highlight over diffuse" (fun () ->
          let engine =
            take_engine "phong highlight"
              (Three.Engine.create ~width:size ~height:size ())
          in
          let root = Three.Scene.create () in
          let material =
            Three.Mesh_phong_material.create
              ~color:(Three.Color.create ~r:0.0 ~g:0.0 ~b:0.0 ())
              ~specular:(Three.Color.create ~r:1.0 ~g:1.0 ~b:1.0 ())
              ~shininess:30.0 ()
          in
          let cube = Three.Mesh.create (Three.Box_geometry.create ()) material in
          O3.add root cube;
          (* Head-on light behind the camera: L and V coincide, so the
             half-vector equals N across the whole front face and the
             Blinn-Phong term saturates everywhere on it. *)
          let sun = Three.Directional_light.create ~intensity:1.0 () in
          V3.set (O3.position sun) 0.0 0.0 5.0;
          O3.add root sun;
          let camera = camera_at () in
          run_frame engine ~root ~camera;
          let snapshot = Three.Engine.snapshot engine in
          expect_pixel snapshot ~width:size ~row:16 ~column:16
            ~expected:(255, 255, 255);
          Three.Engine.destroy engine);

      test "black phong stays black without specular" (fun () ->
          let engine =
            take_engine "phong dark" (Three.Engine.create ~width:size ~height:size ())
          in
          let root = Three.Scene.create () in
          let material =
            Three.Mesh_phong_material.create
              ~color:(Three.Color.create ~r:0.0 ~g:0.0 ~b:0.0 ())
              ~specular:(Three.Color.create ~r:0.0 ~g:0.0 ~b:0.0 ())
              ()
          in
          let cube = Three.Mesh.create (Three.Box_geometry.create ()) material in
          O3.add root cube;
          let sun = Three.Directional_light.create ~intensity:1.0 () in
          V3.set (O3.position sun) 0.0 0.0 5.0;
          O3.add root sun;
          let camera = camera_at () in
          run_frame engine ~root ~camera;
          let snapshot = Three.Engine.snapshot engine in
          expect_pixel snapshot ~width:size ~row:16 ~column:16
            ~expected:(0, 0, 0);
          Three.Engine.destroy engine);

      test "emissive output survives with no lights at all" (fun () ->
          let engine =
            take_engine "emissive" (Three.Engine.create ~width:size ~height:size ())
          in
          let root = Three.Scene.create () in
          let material =
            Three.Mesh_phong_material.create
              ~emissive:(Three.Color.create ~r:0.25 ~g:0.05 ~b:0.0 ())
              ~emissive_intensity:2.0
              ~color:(Three.Color.create ~r:0.0 ~g:0.0 ~b:0.0 ())
              ()
          in
          let cube = Three.Mesh.create (Three.Box_geometry.create ()) material in
          O3.add root cube;
          let camera = camera_at () in
          run_frame engine ~root ~camera;
          let snapshot = Three.Engine.snapshot engine in
          (* Emissive 0.25 * 2 = 0.5 linear -> byte 128 on red; green
             0.05 * 2 = 0.1 linear -> byte 26. Raw framebuffer bytes stay
             linear; sRGB conversion happens at cell write, not here. *)
          expect_pixel snapshot ~width:size ~row:16 ~column:16
            ~expected:(128, 26, 0);
          expect_pixel snapshot ~width:size ~row:13 ~column:19
            ~expected:(128, 26, 0);
          Three.Engine.destroy engine);

      test "point lights fall off with the distance window" (fun () ->
          let probe ~light_z ~distance =
            let engine =
              take_engine "point falloff"
                (Three.Engine.create ~width:size ~height:size ())
            in
            let root = Three.Scene.create () in
            let cube =
              Three.Mesh.create (Three.Box_geometry.create ())
                (Three.Mesh_lambert_material.create
                   ~color:(Three.Color.create ~r:0.5 ~g:0.5 ~b:0.5 ())
                   ())
            in
            O3.add root cube;
            let lamp =
              Three.Point_light.create ~intensity:1.0 ~distance ()
            in
            V3.set (O3.position lamp) 0.0 0.0 light_z;
            O3.add root lamp;
            let camera = camera_at () in
            ignore
              (Three.Engine.render engine ~root ~camera
                  ~clear_color:(0.0, 0.0, 0.0, 1.0) ());
            let value = Three.Engine.snapshot engine in
            let center = pixel value ~width:size ~row:16 ~column:16 in
            Three.Engine.destroy engine;
            center
          in
          (* Legacy punctual window: with a cutoff of ten the front face at
               distance 2.5 sits inside (window 0.75 squared), while the same
               lamp pushed to z=300 lies far outside and contributes nothing.
               A zero cutoff disables attenuation entirely. *)
          let lit = probe ~light_z:3.0 ~distance:10.0 in
          let (_, lg, _) = lit in
          if lg < 40 || lg > 90 then
            fail
              (Printf.sprintf
                 "in-window point light expected ~linear 72 gray, got g=%d"
                 lg);
          let outside = probe ~light_z:300.0 ~distance:10.0 in
          if not (rgb_equal outside (0, 0, 0)) then
            let (cr, cg, cb) = outside in
            fail
              (Printf.sprintf
                 "out-of-window light should leave the cube unlit, got rgb(%d,%d,%d)"
                 cr cg cb));

      test "only the first four visible point lights contribute" (fun () ->
          let engine =
            take_engine "point cap" (Three.Engine.create ~width:size ~height:size ())
          in
          let root = Three.Scene.create () in
          let cube =
            Three.Mesh.create (Three.Box_geometry.create ())
              (Three.Mesh_lambert_material.create
                 ~color:(Three.Color.create ~r:0.5 ~g:0.5 ~b:0.5 ())
                 ())
          in
          O3.add root cube;
          for index = 0 to 5 do
            let lamp =
              Three.Point_light.create
                ~intensity:(Float.of_int (index + 1))
                ()
            in
            V3.set (O3.position lamp) 0.0 0.0 3.0;
            O3.add root lamp
          done;
          let camera = camera_at () in
          run_frame engine ~root ~camera;
          let snapshot = Three.Engine.snapshot engine in
          (* Four slots at intensities 1..4 sum to five times albedo - the
             center clamps to saturated white. A single-slot bug would leave
             it around linear 64. *)
          let (r, g, b) = pixel snapshot ~width:size ~row:16 ~column:16 in
          if r < 250 || g < 250 || b < 250 then
            fail
              (Printf.sprintf
                 "expected clamped white from four summed lights, got rgb(%d,%d,%d)"
                 r g b);
          Three.Engine.destroy engine);
    ]
