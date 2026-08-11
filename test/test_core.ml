open Windtrap

module Scene = Opentui_core.Scene
module Node = Scene.Node

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Opentui_core.Error.message error)

let expect_core_error predicate result =
  match result with
  | Error error when predicate error -> ()
  | Error error -> fail (Opentui_core.Error.message error)
  | Ok _ -> fail "expected a core error"

let expect_rendered result =
  match result with
  | Ok { Scene.status = Scene.Rendered; bytes_written } -> bytes_written
  | Ok { Scene.status = Scene.Skipped; _ } -> fail "expected a rendered frame"
  | Ok { Scene.status = Scene.Failed; _ } -> fail "the core frame failed"
  | Error error -> fail (Opentui_core.Error.message error)

let expect_skipped result =
  match result with
  | Ok { Scene.status = Scene.Skipped; bytes_written } -> bytes_written
  | Ok { Scene.status = Scene.Rendered; _ } -> fail "expected a skipped frame"
  | Ok { Scene.status = Scene.Failed; _ } -> fail "the core frame failed"
  | Error error -> fail (Opentui_core.Error.message error)

let expect_handled target_id result =
  match result with
  | Ok (Scene.Handled target) -> equal int target_id (Node.id target)
  | Ok Scene.Unhandled -> fail "pointer event was not handled"
  | Error error -> fail (Opentui_core.Error.message error)

let () =
  run "opentui-core"
    [
      test "retains text identity across controlled frame flushes" (fun () ->
          let scene = expect_ok (Scene.create ~width:2l ~height:1l) in
          let root = expect_ok (Scene.root scene) in
          let text =
            expect_ok
              (Node.create_text ~parent:root ~width:2.0 ~height:1.0
                 ~text:"AB" ())
          in
          let identity = Node.id text in
          let output = Bytes.create 2 in
          equal int32 2l
            (expect_rendered
               (Scene.flush scene ~force:false ~output));
          equal string "AB" (Bytes.to_string output);
          equal bool false (Node.is_dirty text);
          ignore (expect_ok (Node.set_text text ~text:"CD"));
          equal int identity (Node.id text);
          equal int32 2l
            (expect_rendered
               (Scene.flush scene ~force:false ~output));
          equal string "CD" (Bytes.to_string output);
          equal int32 0l
            (expect_skipped (Scene.flush scene ~force:false ~output));
          Scene.close scene);
      test "detaches destroyed native children before reusing their slot" (fun () ->
          let scene = expect_ok (Scene.create ~width:2l ~height:2l) in
          let root = expect_ok (Scene.root scene) in
          let first =
            expect_ok
              (Node.create_text ~parent:root ~width:2.0 ~height:1.0
                 ~text:"AA" ())
          in
          ignore
            (expect_ok
               (Node.create_text ~parent:root ~width:2.0 ~height:1.0
                  ~text:"BB" ()));
          let output = Bytes.create 4 in
          equal int32 4l
            (expect_rendered (Scene.flush scene ~force:false ~output));
          equal string "AABB" (Bytes.to_string output);
          ignore (expect_ok (Node.destroy first));
          equal bool true (Node.is_destroyed first);
          let replacement =
            expect_ok
              (Node.create_text ~parent:root ~width:2.0 ~height:1.0
                 ~text:"CC" ())
          in
          equal int 3 (Node.id replacement);
          equal int32 4l
            (expect_rendered (Scene.flush scene ~force:false ~output));
          equal string "BBCC" (Bytes.to_string output);
          expect_core_error
            (function Opentui_core.Error.Destroyed -> true | _ -> false)
            (Node.set_text first ~text:"DD");
          expect_core_error
            (function Opentui_core.Error.Cannot_destroy_root -> true | _ -> false)
            (Node.destroy root);
          Scene.close scene);
      test "renders nested text at accumulated scene coordinates" (fun () ->
          let scene = expect_ok (Scene.create ~width:4l ~height:2l) in
          let root = expect_ok (Scene.root scene) in
          let outer =
            expect_ok
              (Node.create_container ~parent:root ~width:3.0 ~height:2.0)
          in
          ignore
            (expect_ok
               (Node.create_container ~parent:outer ~width:2.0 ~height:1.0));
          let inner =
            expect_ok
              (Node.create_container ~parent:outer ~width:2.0 ~height:1.0)
          in
          ignore
            (expect_ok
               (Node.create_text ~parent:inner ~width:2.0 ~height:1.0
                  ~text:"XY" ()));
          let output = Bytes.create 8 in
          equal int32 8l
            (expect_rendered (Scene.flush scene ~force:false ~output));
          equal string "    XY  " (Bytes.to_string output);
          Scene.close scene);
      test "retargets pointer hits after layout mutation" (fun () ->
          let scene = expect_ok (Scene.create ~width:4l ~height:3l) in
          let root = expect_ok (Scene.root scene) in
          let first =
            expect_ok
              (Node.create_text ~parent:root ~width:4.0 ~height:1.0
                 ~text:"AAAA" ())
          in
          let second =
            expect_ok
              (Node.create_text ~parent:root ~width:4.0 ~height:1.0
                 ~text:"BBBB" ())
          in
          let first_id = Node.id first in
          let second_id = Node.id second in
          ignore
            (expect_ok
               (Node.set_pointer_handler first (fun node event ->
                    equal int first_id (Node.id node);
                    equal int 0 event.button;
                    Scene.Stop)));
          ignore
            (expect_ok
               (Node.set_pointer_handler second (fun node event ->
                    equal int second_id (Node.id node);
                    equal int 0 event.button;
                    Scene.Stop)));
          let event y = { Scene.kind = Scene.Down; button = 0; x = 0; y } in
          expect_handled second_id
            (Scene.dispatch_pointer scene (event 1));
          ignore (expect_ok (Node.set_dimensions first ~width:4.0 ~height:2.0));
          equal bool true (Node.is_dirty first);
          expect_handled first_id
            (Scene.dispatch_pointer scene (event 1));
          expect_handled second_id
            (Scene.dispatch_pointer scene (event 2));
          equal bool true (Node.is_dirty first);
          let output = Bytes.create 12 in
          equal int32 12l
            (expect_rendered (Scene.flush scene ~force:false ~output));
          equal string "AAAA    BBBB" (Bytes.to_string output);
          equal bool false (Node.is_dirty first);
          Scene.close scene);
      test "resizes the hit-test root before dispatching" (fun () ->
          let scene = expect_ok (Scene.create ~width:2l ~height:1l) in
          let root = expect_ok (Scene.root scene) in
          let root_id = Node.id root in
          ignore
            (expect_ok
               (Node.set_pointer_handler root (fun node event ->
                    equal int root_id (Node.id node);
                    equal int 1 event.y;
                    Scene.Stop)));
          let event = { Scene.kind = Scene.Down; button = 0; x = 2; y = 1 } in
          (match expect_ok (Scene.dispatch_pointer scene event) with
          | Scene.Unhandled -> ()
          | Scene.Handled _ -> fail "the event exceeded the original bounds");
          ignore (expect_ok (Scene.resize scene ~width:3l ~height:2l));
          expect_handled root_id (Scene.dispatch_pointer scene event);
          let output = Bytes.create 6 in
          equal int32 6l
            (expect_rendered (Scene.flush scene ~force:false ~output));
          Scene.close scene);
      test "recursively removes destroyed subtrees from the scene" (fun () ->
          let scene = expect_ok (Scene.create ~width:4l ~height:2l) in
          let root = expect_ok (Scene.root scene) in
          let branch =
            expect_ok
              (Node.create_container ~parent:root ~width:4.0 ~height:2.0)
          in
          let nested =
            expect_ok
              (Node.create_container ~parent:branch ~width:4.0 ~height:1.0)
          in
          let leaf =
            expect_ok
              (Node.create_text ~parent:nested ~width:4.0 ~height:1.0
                 ~text:"LEAF" ())
          in
          ignore
            (expect_ok
               (Node.set_pointer_handler branch (fun node event ->
                    equal int (Node.id branch) (Node.id node);
                    equal int 0 event.button;
                    Scene.Stop)));
          ignore
            (expect_ok
               (Node.set_pointer_handler leaf (fun node event ->
                    equal int (Node.id leaf) (Node.id node);
                    equal int 0 event.button;
                    Scene.Stop)));
          ignore (expect_ok (Node.destroy branch));
          equal bool true (Node.is_destroyed branch);
          equal bool true (Node.is_destroyed nested);
          equal bool true (Node.is_destroyed leaf);
          equal int 0 (Node.children_count root);
          equal int 0 (Node.children_count branch);
          equal int 0 (Node.children_count nested);
          expect_core_error
            (function Opentui_core.Error.Destroyed -> true | _ -> false)
            (Node.set_pointer_handler branch (fun node event ->
                 equal int (Node.id branch) (Node.id node);
                 equal int 0 event.button;
                 Scene.Stop));
          expect_core_error
            (function Opentui_core.Error.Destroyed -> true | _ -> false)
            (Node.set_pointer_handler nested (fun node event ->
                 equal int (Node.id nested) (Node.id node);
                 equal int 0 event.button;
                 Scene.Stop));
          expect_core_error
            (function Opentui_core.Error.Destroyed -> true | _ -> false)
            (Node.set_dimensions leaf ~width:4.0 ~height:1.0);
          expect_core_error
            (function Opentui_core.Error.Destroyed -> true | _ -> false)
            (Node.destroy leaf);
          (match
             expect_ok
               (Scene.dispatch_pointer scene
                  { Scene.kind = Scene.Down; button = 0; x = 0; y = 0 })
           with
          | Scene.Unhandled -> ()
          | Scene.Handled _ -> fail "destroyed subtree remained hittable");
          let output = Bytes.create 8 in
          equal int32 8l
            (expect_rendered (Scene.flush scene ~force:false ~output));
          equal string "        " (Bytes.to_string output);
          let replacement =
            expect_ok
              (Node.create_text ~parent:root ~width:4.0 ~height:1.0
                 ~text:"NEW!" ())
          in
          ignore
            (expect_ok
               (Node.set_pointer_handler replacement (fun node event ->
                    equal int (Node.id replacement) (Node.id node);
                    equal int 0 event.button;
                    Scene.Stop)));
          expect_handled (Node.id replacement)
            (Scene.dispatch_pointer scene
               { Scene.kind = Scene.Down; button = 0; x = 0; y = 0 });
          equal int32 8l
            (expect_rendered (Scene.flush scene ~force:false ~output));
          equal string "NEW!    " (Bytes.to_string output);
          Scene.close scene);
      test "bubbles pointer events from the hit node to its owner" (fun () ->
          let scene = expect_ok (Scene.create ~width:4l ~height:2l) in
          let root = expect_ok (Scene.root scene) in
          let child =
            expect_ok
              (Node.create_container ~parent:root ~width:4.0 ~height:2.0)
          in
          let child_called = ref false in
          let root_called = ref false in
          ignore
            (expect_ok
               (Node.set_pointer_handler child (fun _node event ->
                    equal int 1 event.button;
                    child_called := true;
                    Scene.Continue)));
          ignore
            (expect_ok
               (Node.set_pointer_handler root (fun _node event ->
                    equal int 1 event.x;
                    equal int 1 event.y;
                    root_called := true;
                    Scene.Stop)));
          let event =
            { Scene.kind = Scene.Down; button = 1; x = 1; y = 1 }
          in
          (match expect_ok (Scene.dispatch_pointer scene event) with
          | Scene.Handled target -> equal int (Node.id child) (Node.id target)
          | Scene.Unhandled -> fail "pointer event was not handled");
          equal bool true !child_called;
          equal bool true !root_called;
          (match
             expect_ok
               (Scene.dispatch_pointer scene
                  { Scene.kind = Scene.Down; button = 1; x = 4; y = 1 })
           with
          | Scene.Unhandled -> ()
          | Scene.Handled _ -> fail "outside pointer event was handled");
          Scene.close scene);
      test "closed scenes invalidate nodes and frame operations" (fun () ->
          let scene = expect_ok (Scene.create ~width:1l ~height:1l) in
          let root = expect_ok (Scene.root scene) in
          let child =
            expect_ok
              (Node.create_text ~parent:root ~width:1.0 ~height:1.0
                 ~text:"X" ())
          in
          Scene.close scene;
          expect_core_error
            (function Opentui_core.Error.Closed -> true | _ -> false)
            (Node.set_text child ~text:"Y");
          expect_core_error
            (function Opentui_core.Error.Closed -> true | _ -> false)
            (Scene.flush scene ~force:true ~output:(Bytes.create 1));
          expect_core_error
            (function Opentui_core.Error.Closed -> true | _ -> false)
            (Scene.dispatch_pointer scene
               { Scene.kind = Scene.Down; button = 1; x = 0; y = 0 }))
    ]
