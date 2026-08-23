open Windtrap

module Three = Opentui_three.Three
module V3 = Three.Vector3
module M4 = Three.Matrix4
module Q = Three.Quaternion

let close ~tolerance a b = Float.abs (a -. b) < tolerance

let expect_close_vec ~tolerance ~expected ~(actual : V3.t) () =
  if
    (not (close ~tolerance expected.(0) actual.x))
    || (not (close ~tolerance expected.(1) actual.y))
    || (not (close ~tolerance expected.(2) actual.z))
  then
    fail
      (Printf.sprintf "vector [%.6f; %.6f; %.6f] expected [%.6f; %.6f; %.6f]"
         actual.x actual.y actual.z expected.(0) expected.(1) expected.(2))

let expect_close_matrix ~tolerance ~expected ~(actual : floatarray) () =
  Array.iteri
    (fun i v ->
      if not (close ~tolerance v (Float.Array.get actual i)) then
        fail
          (Printf.sprintf "matrix[%d] %.9f expected %.9f" i
             (Float.Array.get actual i) v))
    expected

let () =
  run "opentui-three-math"
    [
      test "translation matrix places the offset in the fourth column" (fun () ->
          let m = M4.create () in
          ignore (M4.make_translation m 1.5 (-2.0) 3.25);
          expect_close_matrix ~tolerance:1e-9
            ~expected:
              [| 1.0; 0.0; 0.0; 0.0; 0.0; 1.0; 0.0; 0.0; 0.0; 0.0; 1.0; 0.0;
                 1.5; -2.0; 3.25; 1.0 |]
            ~actual:m ());

      test "perspective produces the reference frustum for canonical inputs"
        (fun () ->
          let p = M4.create () in
          ignore
            (M4.perspective ~fov_degrees:90.0 ~aspect:1.0 ~near:1.0 ~far:3.0 p);
          (* focal length tan(45deg)=1; WebGPU depth maps near=1 far=3
             onto [0..1]: m[10]=3/(1-3)=-1.5, m[14]=3*1/(1-3)=-1.5 *)
          expect_close_matrix ~tolerance:1e-9
            ~expected:
              [| 1.0; 0.0; 0.0; 0.0; 0.0; 1.0; 0.0; 0.0; 0.0; 0.0; -1.5; -1.0;
                 0.0; 0.0; -1.5; 0.0 |]
            ~actual:p ();
          (* a point on the near plane lands on ndc z = 0 *)
          let near_probe = V3.create ~x:0.0 ~y:0.0 ~z:(-1.0) () in
          ignore (M4.transform_point p near_probe);
          if not (close ~tolerance:1e-9 near_probe.z 0.0) then
            fail
              (Printf.sprintf "near plane ndc z %.6f expected 0" near_probe.z);

          (* aspect halves the horizontal scale *)
          ignore
            (M4.perspective ~fov_degrees:90.0 ~aspect:2.0 ~near:1.0 ~far:3.0 p);
          if not (close ~tolerance:1e-9 (Float.Array.get p 0) 0.5) then
            fail "aspect ratio did not divide the x focal term");

      test "quaternion axis-angle rotates X onto Y about Z" (fun () ->
          let q =
            Q.from_axis_angle
              ~axis:(V3.create ~x:0.0 ~y:0.0 ~z:1.0 ())
              ~angle:(Float.pi /. 2.0)
          in
          let m = M4.create () in
          Q.to_matrix4 q m;
          let v = V3.create ~x:1.0 ~y:0.0 ~z:0.0 () in
          ignore (M4.transform_point m v);
          expect_close_vec ~tolerance:1e-9 ~expected:[| 0.0; 1.0; 0.0 |]
            ~actual:v ());

      test "euler to quaternion to euler round trips through matrices"
        (fun () ->
          let e1 = Three.Euler.create ~x:0.4 ~y:(-1.1) ~z:2.2 () in
          let q1 = Three.Euler.to_quaternion ~order:`Xyz e1 in
          let m = M4.create () in
          Q.to_matrix4 q1 m;
          let e2 = Three.Euler.of_quaternion (Q.from_euler_matrix m) in
          let q2 = Three.Euler.to_quaternion ~order:`Xyz e2 in
          let m2 = M4.create () in
          Q.to_matrix4 q2 m2;
          for i = 0 to 11 do
            Printf.printf "DBG[%d] %.9f vs %.9f\n" i (Float.Array.get m i)
              (Float.Array.get m2 i)
          done;
            for i = 0 to M4.size - 1 do
            if
              not
                (close ~tolerance:1e-9 (Float.Array.get m i)
                   (Float.Array.get m2 i))
            then
              fail
                (Printf.sprintf "round trip diverged at [%d]: %.9f vs %.9f" i
                   (Float.Array.get m i)
                   (Float.Array.get m2 i))
          done);

      test "compose matches the translation rotation scale product" (fun () ->
          let position = V3.create ~x:2.0 ~y:(-3.0) ~z:4.0 () in
          let rotation =
            Q.set_from_euler ~x:0.31 ~y:(-0.77) ~z:1.13
          in
          let scale = V3.create ~x:1.5 ~y:2.0 ~z:0.5 () in
          let composed = M4.create () in
          ignore (M4.compose composed position rotation scale);

          let r = M4.create () in
          Q.to_matrix4 rotation r;
          let rs = M4.create () in
          let s_matrix =
            M4.of_array [| scale.x; 0.0; 0.0; 0.0; 0.0; scale.y; 0.0; 0.0;
                           0.0; 0.0; scale.z; 0.0; 0.0; 0.0; 0.0; 1.0 |]
          in
          M4.multiply rs r s_matrix;
          let t = M4.make_translation (M4.create ()) 2.0 (-3.0) 4.0 in
          let trs = M4.create () in
          ignore (M4.multiply trs t rs);
          for i = 0 to M4.size - 1 do
            if
              not
                (close ~tolerance:1e-9 (Float.Array.get composed i)
                   (Float.Array.get trs i))
            then
              fail
                (Printf.sprintf "compose differs from T*R*S at [%d]" i)
          done);

      test "look_at view sends eye to origin and target down negative z"
        (fun () ->
          let view = M4.create () in
          ignore
            (M4.look_at
               ~up:(V3.create ~x:0.0 ~y:1.0 ~z:0.0 ())
               ~eye:(V3.create ~x:0.0 ~y:0.0 ~z:5.0 ())
               ~target:(V3.create ~x:0.0 ~y:0.0 ~z:0.0 ())
               view);
          let eye_point = V3.create ~x:0.0 ~y:0.0 ~z:5.0 () in
          ignore (M4.transform_point view eye_point);
          expect_close_vec ~tolerance:1e-9 ~expected:[| 0.0; 0.0; 0.0 |]
            ~actual:eye_point ();
          let ahead = V3.create ~x:0.0 ~y:0.0 ~z:4.0 () in
          ignore (M4.transform_point view ahead);
          expect_close_vec ~tolerance:1e-9 ~expected:[| 0.0; 0.0; -1.0 |]
            ~actual:ahead ());

      test "invert round trips a general affine matrix" (fun () ->
          let a = M4.of_array [| 2.0; 0.0; 1.0; 0.0; 0.0; 3.0; 0.0; 1.0;
                                 0.5; 0.0; 1.0; 0.0; 1.0; -2.0; 3.0; 1.0 |]
          in
          let inv = M4.create () and product = M4.create () in
          if not (M4.invert a inv) then fail "matrix reported singular";
          M4.multiply product a inv;
          let identity =
            [| 1.0; 0.0; 0.0; 0.0; 0.0; 1.0; 0.0; 0.0; 0.0; 0.0; 1.0; 0.0;
               0.0; 0.0; 0.0; 1.0 |]
          in
          expect_close_matrix ~tolerance:1e-9 ~expected:identity
            ~actual:product ());
    ]
