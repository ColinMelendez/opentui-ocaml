open Windtrap

module Three = Opentui_three.Three
module V3 = Three.Vector3
module M4 = Three.Matrix4
module O3 = Three.Object3d

let close ~tolerance a b = Float.abs (a -. b) < tolerance

let expect_close_vec ~tolerance ~(expected : float array)
    ~(actual : V3.t) () =
  if
    (not (close ~tolerance expected.(0) actual.x))
    || (not (close ~tolerance expected.(1) actual.y))
    || (not (close ~tolerance expected.(2) actual.z))
  then
    fail
      (Printf.sprintf "vector [%.6f; %.6f; %.6f] expected [%.6f; %.6f; %.6f]"
         actual.x actual.y actual.z expected.(0) expected.(1) expected.(2))

let expect_translation ~tolerance ~(expected : float array) ~(actual : O3.t) () =
  let m = O3.matrix_world actual in
  if
    (not (close ~tolerance expected.(0) (Float.Array.get m 12)))
    || (not (close ~tolerance expected.(1) (Float.Array.get m 13)))
    || (not (close ~tolerance expected.(2) (Float.Array.get m 14)))
  then
    fail
      (Printf.sprintf
         "world translation [%.6f; %.6f; %.6f] expected [%.4f; %.4f; %.4f]"
         (Float.Array.get m 12) (Float.Array.get m 13) (Float.Array.get m 14)
         expected.(0) expected.(1) expected.(2))

let () =
  run "opentui-three-scene-graph"
    [
      test "child world matrix composes parent rotation and translation"
        (fun () ->
          let parent = O3.make () in
          let child = O3.make () in
          O3.add parent child;
          V3.set (O3.position parent) 1.0 0.0 0.0;
          parent.rotation.y <- Float.pi /. 2.0;
          child.position.x <- 1.0;
          O3.update_matrix_world parent;
          (* R_y(90) maps the child offset (1,0,0) onto (0,0,-1); adding the
             parent position gives (1,0,-1). *)
          expect_translation ~tolerance:1e-9 ~expected:[| 1.0; 0.0; -1.0 |]
            ~actual:child ());

      test "moving a parent dirties descendants without touching them"
        (fun () ->
          let parent = O3.make () in
          let child = O3.make () in
          O3.add parent child;
          child.position.x <- 2.0;
          O3.update_matrix_world parent;
          expect_translation ~tolerance:1e-9 ~expected:[| 2.0; 0.0; 0.0 |]
            ~actual:child ();
          parent.position.y <- 5.0;
          O3.update_matrix_world parent;
          expect_translation ~tolerance:1e-9 ~expected:[| 2.0; 5.0; 0.0 |]
            ~actual:child ());

      test "matrix_auto_update off freezes the local matrix" (fun () ->
          let node = O3.make () in
          node.matrix_auto_update <- false;
          node.position.z <- 4.0;
          O3.update_matrix_world node;
          expect_translation ~tolerance:1e-9 ~expected:[| 0.0; 0.0; 0.0 |]
            ~actual:node ();
          (* Manual-update nodes compose through Matrix4 themselves, exactly
             as three.js manual-update objects do. *)
          Three.Matrix4.make_translation (O3.matrix node) 0.0 0.0 4.0 |> ignore;
          O3.update_matrix node;
          O3.update_matrix_world node;
          expect_translation ~tolerance:1e-9 ~expected:[| 0.0; 0.0; 4.0 |]
            ~actual:node ());

      test "writing euler angles resyncs the quaternion at update time"
        (fun () ->
          let node = O3.make () in
          node.rotation.x <- Float.pi /. 2.0;
          O3.update_matrix_world node;
          let q = O3.quaternion node in
          if
            (not (close ~tolerance:1e-9 q.x 0.7071067811865475))
            || not (close ~tolerance:1e-9 q.w 0.7071067811865475)
          then
            fail
              (Printf.sprintf "quaternion [%.6f; %.6f] after euler write" q.x
                 q.w);
          (* A direct quaternion write survives until euler changes again. *)
          Three.Quaternion.set q 0.0 0.0 0.0 1.0;
          O3.update_matrix_world node;
          if not (close ~tolerance:1e-12 q.w 1.0) then
            fail "quaternion write was clobbered without an euler change");

      test "look_at points the camera's -Z axis at the target" (fun () ->
          let camera = Three.Perspective_camera.create () in
          V3.set (O3.position camera) 0.0 0.0 3.0;
          O3.look_at ~target:(V3.create ()) camera;
          Three.Perspective_camera.update_matrices camera;
          let view = O3.matrix_world_inverse camera in
          let origin = V3.create () in
          ignore (M4.transform_point view origin);
          expect_close_vec ~tolerance:1e-9 ~expected:[| 0.0; 0.0; -3.0 |]
            ~actual:origin ());

      test "off-axis look_at orients the world forward correctly" (fun () ->
          (* A camera on +X looking at the origin must face -X; a mirrored
             quaternion would report +X here, so this catches basis
             transposition that the straight-on case hides. *)
          let camera = Three.Perspective_camera.create () in
          V3.set (O3.position camera) 3.0 0.0 0.0;
          O3.look_at ~target:(V3.create ()) camera;
          let rotation = M4.create () in
          Three.Quaternion.to_matrix4 (O3.quaternion camera) rotation;
          let forward = V3.create ~x:0.0 ~y:0.0 ~z:(-1.0) () in
          ignore (M4.transform_point rotation forward);
          expect_close_vec ~tolerance:1e-9 ~expected:[| -1.0; 0.0; 0.0 |]
            ~actual:forward ());

      test "rotate_y stays in the node's own space under a rotated parent"
        (fun () ->
          let parent = O3.make () in
          let child = O3.make () in
          O3.add parent child;
          parent.rotation.y <- Float.pi /. 2.0;
          O3.rotate_y child (Float.pi /. 2.0);
          O3.update_matrix_world parent;
          (* Child-local quarter turn sends its +Z onto its own +X; the
             parent's quarter turn then maps that onto -Z. *)
          let forward = V3.create ~x:0.0 ~y:0.0 ~z:1.0 () in
          ignore (M4.transform_point (O3.matrix_world child) forward);
          expect_close_vec ~tolerance:1e-9 ~expected:[| 0.0; 0.0; -1.0 |]
            ~actual:forward ());

      test "remove detaches only from the actual parent" (fun () ->
          let a = O3.make () in
          let b = O3.make () in
          let child = O3.make () in
          O3.add a child;
          O3.remove b child;
          if not (Int.equal (List.length (O3.children a)) 1) then
            fail "remove from a non-parent disturbed the real parent";
          O3.remove a child;
          if not (Int.equal (List.length (O3.children a)) 0) then
            fail "remove left the child attached";
          (match O3.parent child with
          | None -> ()
          | Some _ -> fail "child still references its parent"));

      test "forced updates reach manual-update children" (fun () ->
          let parent = O3.make () in
          let child = O3.make () in
          child.matrix_world_auto_update <- false;
          O3.add parent child;
          O3.update_matrix_world parent;
          expect_translation ~tolerance:1e-9 ~expected:[| 0.0; 0.0; 0.0 |]
            ~actual:child ();
          parent.position.x <- 7.0;
          O3.update_matrix_world parent;
          expect_translation ~tolerance:1e-9 ~expected:[| 7.0; 0.0; 0.0 |]
            ~actual:child ());

      test "rotate_y accumulates in local space" (fun () ->
          let node = O3.make () in
          O3.rotate_y node (Float.pi /. 2.0);
          O3.rotate_y node (Float.pi /. 2.0);
          O3.update_matrix_world node;
          (* Two quarter turns send +Z to -Z. *)
          let forward = V3.create ~x:0.0 ~y:0.0 ~z:1.0 () in
          ignore (M4.transform_point (O3.matrix_world node) forward);
          expect_close_vec ~tolerance:1e-9 ~expected:[| 0.0; 0.0; -1.0 |]
            ~actual:forward ());

      test "translate_z steps along the rotated axis" (fun () ->
          let node = O3.make () in
          node.rotation.y <- Float.pi /. 2.0;
          O3.translate_z node 2.0;
          (* R_y(90) sends local +Z onto world +X: (0,0,2) -> (2,0,0). *)
          O3.update_matrix_world node;
          expect_translation ~tolerance:1e-9 ~expected:[| 2.0; 0.0; 0.0 |]
            ~actual:node ());

      test "adding an ancestor as descendant raises" (fun () ->
          let a = O3.make () in
          let b = O3.make () in
          let c = O3.make () in
          O3.add a b;
          O3.add b c;
          match
            try
              O3.add c a;
              None
            with Invalid_argument _ -> Some ()
          with
          | Some () -> ()
          | None -> fail "cycle through grandchild was accepted");

      test "get_object_by_name finds nodes in the subtree" (fun () ->
          let root = Three.Scene.create () in
          let cube = Three.Mesh.create ~name:"cube"
              (Three.Box_geometry.create ())
              (Three.Mesh_lambert_material.create ())
          in
          ignore cube;
          let holder = O3.make ~name:"holder" () in
          O3.add root holder;
          O3.add holder cube;
          (match O3.get_object_by_name "cube" root with
          | Some found -> if not (found == cube) then fail "wrong node found"
          | None -> fail "named node not found");
          match O3.get_object_by_name "missing" root with
          | None -> ()
          | Some _ -> fail "nonexistent name returned a node");
    ]
