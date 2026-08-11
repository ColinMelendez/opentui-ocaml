open Windtrap

module Scene = Opentui_core.Scene
module Node = Scene.Node
module Box = Scene.Box
module Text = Scene.Text

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
      test "typed box and text renderables share retained identity and teardown"
        (fun () ->
          let scene = expect_ok (Scene.create ~width:6l ~height:3l) in
          let root = expect_ok (Scene.root scene) in
          let box =
            expect_ok
              (Box.create ~parent:root ~width:6.0 ~height:3.0
                 ~border:Scene.Single ~should_fill:false ())
          in
          let text =
            expect_ok
              (Text.create ~parent:(Box.node box) ~width:4.0 ~height:1.0
                 ~text:"AB" ())
          in
          (match Node.kind (Box.node box) with
          | Scene.Node.Box -> ()
          | Scene.Node.Text -> fail "typed box lost its kind");
          (match Node.kind (Text.node text) with
          | Scene.Node.Text -> ()
          | Scene.Node.Box -> fail "typed text lost its kind");
          let text_id = Node.id (Text.node text) in
          equal string "AB" (Text.content text);
          let output = Bytes.create 64 in
          let written = expect_rendered (Scene.flush scene ~force:false ~output) in
          equal int32 46l written;
          equal string "┌────┐│AB  │└────┘"
            (Bytes.sub_string output 0 (Int32.to_int written));
          ignore (expect_ok (Text.set text ~content:"AB"));
          ignore
            (expect_ok
               (Box.set_border box ~border:Scene.Single));
          equal int32 0l
            (expect_skipped (Scene.flush scene ~force:false ~output));
          ignore (expect_ok (Text.set text ~content:"CD"));
          (match Box.border box with
          | Scene.Single -> ()
          | _ -> fail "typed box did not retain its border style");
          let hits = ref 0 in
          ignore
            (expect_ok
               (Node.set_pointer_handler (Text.node text) (fun node event ->
                    equal int text_id (Node.id node);
                    equal int 1 event.x;
                    hits := !hits + 1;
                    Scene.Stop)));
          expect_handled text_id
            (Scene.dispatch_pointer scene
               { Scene.kind = Scene.Down; button = 0; x = 1; y = 1 });
          equal int 1 !hits;
          ignore (expect_ok (Box.set_border box ~border:Scene.Double));
          let written = expect_rendered (Scene.flush scene ~force:false ~output) in
          equal int32 46l written;
          equal string "╔════╗║CD  ║╚════╝"
            (Bytes.sub_string output 0 (Int32.to_int written));
          ignore (expect_ok (Box.set_border box ~border:Scene.No_border));
          let written = expect_rendered (Scene.flush scene ~force:false ~output) in
          equal int32 18l written;
          equal string ("CD" ^ String.make 16 ' ')
            (Bytes.sub_string output 0 (Int32.to_int written));
          equal int text_id (Node.id (Text.node text));
          ignore (expect_ok (Node.destroy (Box.node box)));
          equal bool true (Node.is_destroyed (Box.node box));
          equal bool true (Node.is_destroyed (Text.node text));
          Scene.close scene);
      test "moves retained children without recreating or losing teardown" (fun () ->
          let scene = expect_ok (Scene.create ~width:4l ~height:2l) in
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
          let output = Bytes.create 8 in
          equal int32 8l
            (expect_rendered (Scene.flush scene ~force:false ~output));
          equal string "AAAABBBB" (Bytes.to_string output);
          equal int first_id (Node.id first);
          equal int second_id (Node.id second);
          expect_core_error
            (function Opentui_core.Error.Invalid_child_index -> true | _ -> false)
            (Node.move_to_index first ~index:2);
          equal int32 0l
            (expect_skipped (Scene.flush scene ~force:false ~output));
          equal string "AAAABBBB" (Bytes.to_string output);
          ignore (expect_ok (Node.move_to_index first ~index:1));
          equal int32 8l
            (expect_rendered (Scene.flush scene ~force:false ~output));
          equal string "BBBBAAAA" (Bytes.to_string output);
          ignore (expect_ok (Node.destroy second));
          equal bool true (Node.is_destroyed second);
          let replacement =
            expect_ok
              (Node.create_text ~parent:root ~width:4.0 ~height:1.0
                 ~text:"CCCC" ())
          in
          equal int32 8l
            (expect_rendered (Scene.flush scene ~force:false ~output));
          equal string "AAAACCCC" (Bytes.to_string output);
          ignore (expect_ok (Node.move_to_index replacement ~index:0));
          equal int first_id (Node.id first);
          equal int32 8l
            (expect_rendered (Scene.flush scene ~force:false ~output));
          equal string "CCCCAAAA" (Bytes.to_string output);
          expect_core_error
            (function Opentui_core.Error.Cannot_move_root -> true | _ -> false)
            (Node.move_to_index root ~index:0);
          Scene.close scene);
      test "moves nested subtrees and retargets pointer hits before teardown" (fun () ->
          let scene = expect_ok (Scene.create ~width:4l ~height:2l) in
          let root = expect_ok (Scene.root scene) in
          let first_branch =
            expect_ok
              (Node.create_box ~parent:root ~width:4.0 ~height:1.0 ())
          in
          let first_leaf =
            expect_ok
              (Node.create_text ~parent:first_branch ~width:4.0 ~height:1.0
                 ~text:"AAAA" ())
          in
          let second_branch =
            expect_ok
              (Node.create_box ~parent:root ~width:4.0 ~height:1.0 ())
          in
          let second_leaf =
            expect_ok
              (Node.create_text ~parent:second_branch ~width:4.0 ~height:1.0
                 ~text:"BBBB" ())
          in
          let first_branch_id = Node.id first_branch in
          let first_leaf_id = Node.id first_leaf in
          let second_branch_id = Node.id second_branch in
          let second_leaf_id = Node.id second_leaf in
          ignore
            (expect_ok
               (Node.set_pointer_handler first_leaf (fun node event ->
                    equal int first_leaf_id (Node.id node);
                    equal int 0 event.x;
                    Scene.Stop)));
          ignore
            (expect_ok
               (Node.set_pointer_handler second_leaf (fun node event ->
                    equal int second_leaf_id (Node.id node);
                    equal int 0 event.x;
                    Scene.Stop)));
          let output = Bytes.create 8 in
          equal int32 8l
            (expect_rendered (Scene.flush scene ~force:false ~output));
          equal string "AAAABBBB" (Bytes.to_string output);
          let pointer_event y =
            { Scene.kind = Scene.Down; button = 0; x = 0; y }
          in
          expect_handled second_leaf_id
            (Scene.dispatch_pointer scene (pointer_event 1));
          ignore (expect_ok (Node.move_to_index first_branch ~index:1));
          equal int first_branch_id (Node.id first_branch);
          equal int first_leaf_id (Node.id first_leaf);
          equal int second_branch_id (Node.id second_branch);
          equal int second_leaf_id (Node.id second_leaf);
          expect_handled second_leaf_id
            (Scene.dispatch_pointer scene (pointer_event 0));
          expect_handled first_leaf_id
            (Scene.dispatch_pointer scene (pointer_event 1));
          equal int32 8l
            (expect_rendered (Scene.flush scene ~force:false ~output));
          equal string "BBBBAAAA" (Bytes.to_string output);
          ignore (expect_ok (Node.destroy first_branch));
          equal bool true (Node.is_destroyed first_branch);
          equal bool true (Node.is_destroyed first_leaf);
          equal int 0 (Node.children_count first_branch);
          equal int 1 (Node.children_count root);
          expect_handled second_leaf_id
            (Scene.dispatch_pointer scene (pointer_event 0));
          (match
             expect_ok (Scene.dispatch_pointer scene (pointer_event 1))
           with
          | Scene.Unhandled -> ()
          | Scene.Handled _ -> fail "destroyed nested leaf remained hittable");
          equal int32 8l
            (expect_rendered (Scene.flush scene ~force:false ~output));
          equal string "BBBB    " (Bytes.to_string output);
          Scene.close scene);
      test
        "preserves nested identity and bubbling across reorder, retry, and teardown"
        (fun () ->
          let scene = expect_ok (Scene.create ~width:4l ~height:2l) in
          let root = expect_ok (Scene.root scene) in
          let first_branch =
            expect_ok
              (Node.create_box ~parent:root ~width:4.0 ~height:1.0 ())
          in
          let first_leaf =
            expect_ok
              (Node.create_text ~parent:first_branch ~width:4.0 ~height:1.0
                 ~text:"AAAA" ())
          in
          let second_branch =
            expect_ok
              (Node.create_box ~parent:root ~width:4.0 ~height:1.0 ())
          in
          let second_leaf =
            expect_ok
              (Node.create_text ~parent:second_branch ~width:4.0 ~height:1.0
                 ~text:"BBBB" ())
          in
          let first_branch_id = Node.id first_branch in
          let first_leaf_id = Node.id first_leaf in
          let second_branch_id = Node.id second_branch in
          let second_leaf_id = Node.id second_leaf in
          let first_leaf_hits = ref 0 in
          let first_branch_hits = ref 0 in
          let second_leaf_hits = ref 0 in
          let second_branch_hits = ref 0 in
          let leaf_handler expected_id hits node event =
            equal int expected_id (Node.id node);
            equal int 0 event.Scene.button;
            hits := !hits + 1;
            Scene.Continue
          in
          let branch_handler expected_id hits node event =
            equal int expected_id (Node.id node);
            equal int 0 event.Scene.button;
            hits := !hits + 1;
            Scene.Stop
          in
          ignore
            (expect_ok
               (Node.set_pointer_handler first_leaf
                  (leaf_handler first_leaf_id first_leaf_hits)));
          ignore
            (expect_ok
               (Node.set_pointer_handler first_branch
                  (branch_handler first_branch_id first_branch_hits)));
          ignore
            (expect_ok
               (Node.set_pointer_handler second_leaf
                  (leaf_handler second_leaf_id second_leaf_hits)));
          ignore
            (expect_ok
               (Node.set_pointer_handler second_branch
                  (branch_handler second_branch_id second_branch_hits)));
          let output = Bytes.create 8 in
          equal int32 8l
            (expect_rendered (Scene.flush scene ~force:false ~output));
          equal string "AAAABBBB" (Bytes.to_string output);
          let event y = { Scene.kind = Scene.Down; button = 0; x = 0; y } in
          expect_handled first_leaf_id
            (Scene.dispatch_pointer scene (event 0));
          equal int 1 !first_leaf_hits;
          equal int 1 !first_branch_hits;
          ignore (expect_ok (Node.move_to_index first_branch ~index:1));
          equal int first_branch_id (Node.id first_branch);
          equal int first_leaf_id (Node.id first_leaf);
          equal int second_branch_id (Node.id second_branch);
          equal int second_leaf_id (Node.id second_leaf);
          expect_handled second_leaf_id
            (Scene.dispatch_pointer scene (event 0));
          expect_handled first_leaf_id
            (Scene.dispatch_pointer scene (event 1));
          equal int 2 !first_leaf_hits;
          equal int 2 !first_branch_hits;
          equal int 1 !second_leaf_hits;
          equal int 1 !second_branch_hits;
          ignore (expect_ok (Node.set_text first_leaf ~text:"CCCC"));
          expect_core_error
            (function
              | Opentui_core.Error.Native
                  (Opentui_native.Error.Native
                     Opentui_raw.Error.Output_too_small) -> true
              | _ -> false)
            (Scene.flush scene ~force:false ~output:(Bytes.create 1));
          equal bool true (Node.is_dirty first_leaf);
          equal int32 8l
            (expect_rendered (Scene.flush scene ~force:false ~output));
          equal string "BBBBCCCC" (Bytes.to_string output);
          equal bool false (Node.is_dirty first_leaf);
          equal int32 0l
            (expect_skipped (Scene.flush scene ~force:false ~output));
          ignore (expect_ok (Node.destroy second_branch));
          equal bool true (Node.is_destroyed second_branch);
          equal bool true (Node.is_destroyed second_leaf);
          equal int 0 (Node.children_count second_branch);
          equal int 1 (Node.children_count root);
          expect_handled first_leaf_id
            (Scene.dispatch_pointer scene (event 0));
          equal int 3 !first_leaf_hits;
          equal int 3 !first_branch_hits;
          equal int32 8l
            (expect_rendered (Scene.flush scene ~force:false ~output));
          equal string "CCCC    " (Bytes.to_string output);
          Scene.close scene);
      test "retains dirty state after an output-capacity failure" (fun () ->
          let scene = expect_ok (Scene.create ~width:2l ~height:1l) in
          let root = expect_ok (Scene.root scene) in
          let text =
            expect_ok
              (Node.create_text ~parent:root ~width:2.0 ~height:1.0
                 ~text:"AB" ())
          in
          let undersized = Bytes.create 1 in
          expect_core_error
            (function
              | Opentui_core.Error.Native
                  (Opentui_native.Error.Native
                     Opentui_raw.Error.Output_too_small) -> true
              | _ -> false)
            (Scene.flush scene ~force:false ~output:undersized);
          equal bool true (Node.is_dirty text);
          let output = Bytes.create 2 in
          equal int32 2l
            (expect_rendered (Scene.flush scene ~force:false ~output));
          equal string "AB" (Bytes.to_string output);
          equal bool false (Node.is_dirty text);
          equal int32 0l
            (expect_skipped (Scene.flush scene ~force:false ~output));
          expect_core_error
            (function
              | Opentui_core.Error.Native
                  (Opentui_native.Error.Native
                     Opentui_raw.Error.Output_too_small) -> true
              | _ -> false)
            (Scene.flush scene ~force:true ~output:undersized);
          equal int32 2l
            (expect_rendered (Scene.flush scene ~force:false ~output));
          equal string "AB" (Bytes.to_string output);
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
              (Node.create_box ~parent:root ~width:3.0 ~height:2.0 ())
          in
          ignore
            (expect_ok
               (Node.create_box ~parent:outer ~width:2.0 ~height:1.0 ()));
          let inner =
            expect_ok
              (Node.create_box ~parent:outer ~width:2.0 ~height:1.0 ())
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
              (Node.create_box ~parent:root ~width:4.0 ~height:2.0 ())
          in
          let nested =
            expect_ok
              (Node.create_box ~parent:branch ~width:4.0 ~height:1.0 ())
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
              (Node.create_box ~parent:root ~width:4.0 ~height:2.0 ())
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
