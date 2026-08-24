open Windtrap

module Three = Opentui_three.Three
module O3 = Three.Object3d
module V3 = Three.Vector3

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
  | Error error ->
      fail (what ^ ": " ^ Opentui_wgpu.Wgpu.Error.message error)

let pixel snapshot ~width ~row ~column =
  let base = ((row * width) + column) * 4 in
  ( Char.code snapshot.[base],
    Char.code snapshot.[base + 1],
    Char.code snapshot.[base + 2] )

let rgb_equal (ar, ag, ab) (br, bg, bb) =
  Int.equal ar br && Int.equal ag bg && Int.equal ab bb

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

(* A 50-degree camera one square aspect wide, sitting three units down +Z,
   matches every expected-value computation below. *)
let camera_at ?(z = 3.0) () =
  let camera =
    Three.Perspective_camera.create ~fov_degrees:50.0 ~aspect:1.0 ()
  in
  V3.set (O3.position camera) 0.0 0.0 z;
  camera

let standard_lights () =
  let ambient = Three.Ambient_light.create ~intensity:0.25 () in
  let directional = Three.Directional_light.create ~intensity:1.0 () in
  (* Shining straight down -Z toward the default origin target. *)
  V3.set (O3.position directional) 0.0 0.0 5.0;
  (ambient, directional)

let add_pair root (a, b) =
  O3.add root a;
  O3.add root b

let size = 32

let background = (0, 0, 255)

let run_frame ?(clear_color = (0.0, 0.0, 1.0, 1.0)) engine ~root ~camera =
  expect_ok "render"
    (Three.Engine.render engine ~root ~camera ~clear_color ())

let () =
  run "opentui-three-render"
    [
     test "unlit cube renders flat albedo regardless of lights" (fun () ->
          let engine = take_engine "the unlit cube" (Three.Engine.create ~width:size ~height:size ()) in
          let root = Three.Scene.create () in
          let cube =
            Three.Mesh.create
              (Three.Box_geometry.create ())
              (Three.Mesh_basic_material.create
                 ~color:(Three.Color.from_hex_int 0xff0000)
                 ())
          in
          O3.add root cube;
          add_pair root (standard_lights ());
          let camera = camera_at () in
          run_frame engine ~root ~camera;
          let snapshot = Three.Engine.snapshot engine in
          List.iter
            (fun (row, column) ->
              expect_pixel snapshot ~width:size ~row ~column
                ~expected:(255, 0, 0))
            [ (16, 16); (13, 19); (19, 13) ];
          List.iter
            (fun (row, column) ->
              expect_pixel snapshot ~width:size ~row ~column
                ~expected:background)
            [ (2, 2); (29, 29); (16, 2) ];
          Three.Engine.destroy engine);

      test "resize rebuilds the surface and keeps rendering" (fun () ->
          let engine = take_engine "the resize check" (Three.Engine.create ~width:size ~height:size ()) in
          expect_ok "resize" (Three.Engine.resize engine ~width:16 ~height:8);
          let root = Three.Scene.create () in
          let cube =
            Three.Mesh.create (Three.Box_geometry.create ())
              (Three.Mesh_lambert_material.create
                 ~color:(Three.Color.create ~r:0.5 ~g:0.5 ~b:0.5 ())
                 ())
          in
          O3.add root cube;
          add_pair root (standard_lights ());
          let camera = camera_at () in
          run_frame engine ~root ~camera;
          let snapshot = Three.Engine.snapshot engine in
          if not (Int.equal (String.length snapshot) (16 * 8 * 4)) then
            fail
              (Printf.sprintf "resized snapshot holds %d bytes"
                 (String.length snapshot));
          (* The cube still fills the middle of the narrower viewport. *)
          expect_pixel snapshot ~width:16 ~row:4 ~column:8
            ~expected:(159, 159, 159);
          expect_pixel snapshot ~width:16 ~row:0 ~column:15
            ~expected:background;
          Three.Engine.destroy engine);
       test "lambert cube shades front faces brighter than sides" (fun () ->
          let engine = take_engine "the lambert cube" (Three.Engine.create ~width:size ~height:size ()) in
          let root = Three.Scene.create () in
          let albedo = Three.Color.create ~r:0.5 ~g:0.5 ~b:0.5 () in
          let cube =
            Three.Mesh.create (Three.Box_geometry.create ())
              (Three.Mesh_lambert_material.create ~color:albedo ())
          in
          O3.add root cube;
          add_pair root (standard_lights ());
          let camera = camera_at () in
          run_frame engine ~root ~camera;
          let snapshot = Three.Engine.snapshot engine in
          (* Head-on lighting: N.L = 1, so linear 0.5*(0.25 + 1.0) = 0.625
             encodes as byte 159; perpendicular faces keep ambient only,
             0.125 -> 32. *)
          List.iter
            (fun (row, column) ->
              expect_pixel snapshot ~width:size ~row ~column
                ~expected:(159, 159, 159))
            [ (16, 16); (13, 19); (19, 13) ];
          List.iter
            (fun (row, column) ->
              expect_pixel snapshot ~width:size ~row ~column
                ~expected:background)
            [ (2, 2); (29, 29) ];
          Three.Engine.destroy engine);

      test "pitched lambert cube shows exactly two shaded classes" (fun () ->
          let engine = take_engine "the rotated cube" (Three.Engine.create ~width:size ~height:size ()) in
          let root = Three.Scene.create () in
          let albedo = Three.Color.create ~r:0.5 ~g:0.5 ~b:0.5 () in
          let cube =
            Three.Mesh.create (Three.Box_geometry.create ())
              (Three.Mesh_lambert_material.create ~color:albedo ())
          in
          O3.add root cube;
          cube.rotation.x <- Float.pi /. 6.0;
          add_pair root (standard_lights ());
          let camera = camera_at () in
          run_frame engine ~root ~camera;
          let snapshot = Three.Engine.snapshot engine in
          (* Pitching 30 degrees tips the top face toward the light path:
             the former +z face shades at 0.5*(0.25+cos30) -> byte 142 and
             the top face at 0.5*(0.25+sin30) -> 96. Nothing else may appear
             inside the silhouette. *)
          let front = ref false and top = ref false in
          for row = 0 to size - 1 do
            for column = 0 to size - 1 do
              let (r, g, b) = pixel snapshot ~width:size ~row ~column in
              if not (rgb_equal (r, g, b) background) then begin
                if Int.abs (r - 142) <= 2 && Int.abs (g - 142) <= 2 then
                  front := true
                else if Int.abs (r - 96) <= 2 && Int.abs (g - 96) <= 2 then
                  top := true
                else
                  fail
                    (Printf.sprintf "unexpected shade rgb(%d,%d,%d) at (%d,%d)"
                       r g b row column)
              end
            done
          done;
          if not !front then fail "no front-face class found in pitched cube";
          if not !top then fail "no top-face class found";
          Three.Engine.destroy engine);

      test "two meshes draw independently through separate uniforms" (fun () ->
          let engine = take_engine "the two-cube scene" (Three.Engine.create ~width:size ~height:size ()) in
          let root = Three.Scene.create () in
          let left =
            Three.Mesh.create
              (Three.Box_geometry.create ())
              (Three.Mesh_lambert_material.create
                 ~color:(Three.Color.create ~r:0.5 ~g:0.5 ~b:0.5 ())
                 ())
          in
          V3.set (O3.position left) (-1.2) 0.0 0.0;
          let right =
            Three.Mesh.create
              (Three.Box_geometry.create ())
              (Three.Mesh_basic_material.create
                 ~color:(Three.Color.from_hex_int 0x00ff00)
                 ())
          in
          V3.set (O3.position right) 1.2 0.0 0.0;
          O3.add root left;
          O3.add root right;
          add_pair root (standard_lights ());
          let camera = camera_at () in
          run_frame engine ~root ~camera;
          let snapshot = Three.Engine.snapshot engine in
          expect_pixel snapshot ~width:size ~row:16 ~column:3
            ~expected:(159, 159, 159);
          expect_pixel snapshot ~width:size ~row:16 ~column:29
            ~expected:(0, 255, 0);
          expect_pixel snapshot ~width:size ~row:16 ~column:16
            ~expected:background;
          Three.Engine.destroy engine);

      test "renders are deterministic across repeated frames" (fun () ->
          let engine = take_engine "the determinism check" (Three.Engine.create ~width:size ~height:size ()) in
          let root = Three.Scene.create () in
          let cube =
            Three.Mesh.create (Three.Box_geometry.create ())
              (Three.Mesh_lambert_material.create
                 ~color:(Three.Color.create ~r:0.5 ~g:0.5 ~b:0.5 ())
                 ())
          in
          O3.add root cube;
          add_pair root (standard_lights ());
          let camera = camera_at () in
          run_frame engine ~root ~camera;
          let first = Three.Engine.snapshot engine in
          run_frame engine ~root ~camera;
          let second = Three.Engine.snapshot engine in
          if not (String.equal first second) then
            fail "two identical renders produced different bytes";
          Three.Engine.destroy engine);

      test "hidden subtrees contribute no pixels" (fun () ->
          let engine = take_engine "visibility culling" (Three.Engine.create ~width:size ~height:size ()) in
          let root = Three.Scene.create () in
          let holder = Three.Group.create () in
          let cube =
            Three.Mesh.create (Three.Box_geometry.create ())
              (Three.Mesh_basic_material.create
                 ~color:(Three.Color.from_hex_int 0xff0000)
                 ())
          in
          O3.add holder cube;
          O3.add root holder;
          O3.set_visible holder false;
          let camera = camera_at () in
          run_frame engine ~root ~camera;
          let snapshot = Three.Engine.snapshot engine in
          expect_pixel snapshot ~width:size ~row:16 ~column:16
            ~expected:background;
          Three.Engine.destroy engine);

      test "draw list encodes near meshes before far meshes" (fun () ->
          (* Without a depth buffer the LAST encoded draw wins on overlap.
             Front-to-back sorting must therefore encode the near cube
             first, letting the far cube paint over it - this pins the
             documented phase-1 ordering contract. *)
          let engine = take_engine "draw order" (Three.Engine.create ~width:size ~height:size ()) in
          let root = Three.Scene.create () in
          let near_cube =
            Three.Mesh.create (Three.Box_geometry.create ())
              (Three.Mesh_basic_material.create
                 ~color:(Three.Color.from_hex_int 0xff0000)
                 ())
          in
          V3.set (O3.position near_cube) 0.0 0.0 1.0;
          let far_cube =
            Three.Mesh.create (Three.Box_geometry.create ())
              (Three.Mesh_basic_material.create
                 ~color:(Three.Color.from_hex_int 0x0000ff)
                 ())
          in
          V3.set (O3.position far_cube) 0.0 0.0 (-1.0);
          O3.add root near_cube;
          O3.add root far_cube;
          add_pair root (standard_lights ());
          let camera = camera_at () in
          run_frame engine ~root ~camera;
          let snapshot = Three.Engine.snapshot engine in
          expect_pixel snapshot ~width:size ~row:16 ~column:16
            ~expected:(0, 0, 255);
          Three.Engine.destroy engine);

      test "swapping geometry invalidates the cached upload" (fun () ->
          let engine = take_engine "geometry swap" (Three.Engine.create ~width:size ~height:size ()) in
          let root = Three.Scene.create () in
          let material =
            Three.Mesh_basic_material.create
              ~color:(Three.Color.from_hex_int 0xff0000)
              ()
          in
          let small = Three.Box_geometry.create ~width:1.0 ~height:1.0 ~depth:1.0 () in
          let big = Three.Box_geometry.create ~width:2.6 ~height:2.6 ~depth:2.6 () in
          let cube = Three.Mesh.create small material in
          O3.add root cube;
          let camera = camera_at () in
          run_frame engine ~root ~camera;
          let before = Three.Engine.snapshot engine in
          (* The big box fills more of the frame; reusing the stale upload
             would leave the silhouette unchanged. *)
          Three.Mesh.set_geometry cube big;
          run_frame engine ~root ~camera;
          let after = Three.Engine.snapshot engine in
          if String.equal before after then
            fail "geometry swap kept rendering the old upload";
          (* The 2.6-unit box projects past the frame edges; its center is
             still red and the frame corners are inside the silhouette too. *)
          expect_pixel after ~width:size ~row:16 ~column:16
            ~expected:(255, 0, 0);
          expect_pixel after ~width:size ~row:1 ~column:30
            ~expected:(255, 0, 0);
          Three.Engine.destroy engine);

   ]
