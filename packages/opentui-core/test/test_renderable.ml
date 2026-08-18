open Windtrap

module Core = Opentui_core
module Renderer = Core.Renderer
module Context = Core.Render_context
module Renderable = Core.Renderable

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Core.Error.message error)

let expect_error expected result =
  match result with
  | Ok _ -> fail "expected an error"
  | Error actual ->
      equal bool true
        (match expected, actual with
        | Core.Error.Closed, Core.Error.Closed
        | Core.Error.Destroyed, Core.Error.Destroyed
        | Core.Error.Owner_mismatch, Core.Error.Owner_mismatch
        | Core.Error.Not_child, Core.Error.Not_child
        | Core.Error.Invalid_anchor, Core.Error.Invalid_anchor
        | Core.Error.Unsupported, Core.Error.Unsupported -> true
        | _ -> false)

let assert_child_ids renderable expected =
  let rec compare actual expected =
    match actual, expected with
    | [], [] -> ()
    | actual :: actual_rest, expected :: expected_rest ->
        equal string expected (Renderable.id actual);
        compare actual_rest expected_rest
    | [], _ :: _ | _ :: _, [] -> fail "unexpected child count"
  in
  compare (Renderable.children renderable) expected

let make_child context ?id ?behavior () =
  expect_ok (Renderable.Private.create context ?id ?behavior ())

let () =
  run "opentui-core-renderable"
    [
      test "renderer owns a root and independent children attach without sharing Yoga ownership"
        (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:20l ~height:10l ()) in
          let context = Renderer.context renderer in
          let root = Renderer.root renderer in
          let child = make_child context ~id:"child" () in
          ignore (expect_ok (Renderable.set_width child (Core.Yoga.Point 4.0)));
          ignore (expect_ok (Renderable.set_height child (Core.Yoga.Point 2.0)));
          ignore
            (expect_ok
               (Renderable.Private.attach ~parent:root ~child ~index:0));
          equal int 1 (Renderable.child_count root);
          equal bool true
            (match Renderable.find_child_by_id root "child" with
            | Some found -> found == child
            | None -> false);
          equal bool true
            (match Renderable.parent child with
            | Some parent -> parent == root
            | None -> false);
          ignore (expect_ok (Renderer.render renderer ~force:true));
          equal (float 0.0001) 4.0 (Renderable.width child);
          equal (float 0.0001) 2.0 (Renderable.height child);
          equal bool true
            (match expect_ok (Renderer.hit_test renderer ~x:1 ~y:1) with
            | Some found -> found == child
            | None -> false);
          Renderer.destroy renderer;
          equal bool true (Renderable.is_destroyed root);
          equal bool true (Renderable.is_destroyed child);
          expect_error Core.Error.Closed (Renderable.request_render child));
      test "detaching preserves the renderable and its Yoga node until destruction"
        (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:8l ~height:4l ()) in
          let root = Renderer.root renderer in
          let child = make_child (Renderer.context renderer) () in
          ignore
            (expect_ok
               (Renderable.Private.attach ~parent:root ~child ~index:0));
          ignore
            (expect_ok (Renderable.Private.detach ~parent:root ~child));
          equal int 0 (Renderable.child_count root);
          equal bool true (Option.is_none (Renderable.parent child));
          ignore (expect_ok (Renderable.set_opacity child 0.5));
          equal bool true (Renderable.is_dirty child);
          Renderable.destroy child;
          equal bool true (Renderable.is_destroyed child);
          expect_error Core.Error.Destroyed (Renderable.request_render child);
          Renderer.destroy renderer);
      test "cross-renderer attachment fails before changing either tree"
        (fun () ->
          let left = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:4l ~height:2l ()) in
          let right = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:4l ~height:2l ()) in
          let child = make_child (Renderer.context left) () in
          ignore
            (expect_ok
               (Renderable.Private.attach ~parent:(Renderer.root left) ~child
                  ~index:0));
          expect_error Core.Error.Owner_mismatch
            (Renderable.Private.attach ~parent:(Renderer.root right) ~child
               ~index:0);
          equal int 1 (Renderable.child_count (Renderer.root left));
          equal int 0 (Renderable.child_count (Renderer.root right));
          Renderer.destroy left;
          Renderer.destroy right);
      test "same-parent attachment reorders without removal callbacks or live-count churn"
        (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:8l ~height:4l ()) in
          let context = Renderer.context renderer in
          let removals = ref 0 in
          let behavior =
            Renderable.Private.make_behavior
              ~on_remove:(fun _ -> removals := !removals + 1)
              ()
          in
          let first = make_child context ~id:"first" () in
          let second = make_child context ~id:"second" ~behavior () in
          ignore
            (expect_ok
               (Renderable.Private.attach ~parent:(Renderer.root renderer)
                  ~child:first ~index:0));
          ignore
            (expect_ok
               (Renderable.Private.attach ~parent:(Renderer.root renderer)
                  ~child:second ~index:1));
          ignore
            (expect_ok
               (Renderable.Private.attach ~parent:(Renderer.root renderer)
                  ~child:second ~index:0));
          (match Renderable.children (Renderer.root renderer) with
          | current :: _ -> equal bool true (current == second)
          | [] -> fail "reordered child disappeared");
          equal int 0
            (expect_ok
               (Renderable.Private.attach ~parent:(Renderer.root renderer)
                  ~child:second ~index:0));
          equal int 0 !removals;
          Renderer.destroy renderer);
      test "forward indexed moves and insert-before preserve Yoga layout order"
        (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:10l ~height:8l ()) in
          let context = Renderer.context renderer in
          let root = Renderer.root renderer in
          let first = make_child context ~id:"first" () in
          let second = make_child context ~id:"second" () in
          let third = make_child context ~id:"third" () in
          ignore (expect_ok (Renderable.set_height first (Core.Yoga.Point 1.0)));
          ignore (expect_ok (Renderable.set_height second (Core.Yoga.Point 2.0)));
          ignore (expect_ok (Renderable.set_height third (Core.Yoga.Point 3.0)));
          ignore (expect_ok (Renderable.Private.attach ~parent:root ~child:first ~index:0));
          ignore (expect_ok (Renderable.Private.attach ~parent:root ~child:second ~index:1));
          ignore (expect_ok (Renderable.Private.attach ~parent:root ~child:third ~index:2));
          equal int 1
            (expect_ok (Renderable.Private.attach ~parent:root ~child:first ~index:2));
          assert_child_ids root [ "second"; "first"; "third" ];
          ignore (expect_ok (Renderer.render renderer ~force:true));
          equal (float 0.0001) 0.0 (Renderable.y second);
          equal (float 0.0001) 2.0 (Renderable.y first);
          equal (float 0.0001) 3.0 (Renderable.y third);
          equal int 0
            (expect_ok
               (Renderable.Private.insert_before ~parent:root ~child:third
                  ~anchor:second));
          assert_child_ids root [ "third"; "second"; "first" ];
          ignore (expect_ok (Renderer.render renderer ~force:true));
          equal (float 0.0001) 0.0 (Renderable.y third);
          equal (float 0.0001) 3.0 (Renderable.y second);
          equal (float 0.0001) 5.0 (Renderable.y first);
          Renderer.destroy renderer);
      test "descendant lookup uses depth-first pre-order"
        (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:8l ~height:4l ()) in
          let context = Renderer.context renderer in
          let root = Renderer.root renderer in
          let branch = make_child context ~id:"branch" () in
          let deep = make_child context ~id:"target" () in
          let sibling = make_child context ~id:"target" () in
          ignore (expect_ok (Renderable.Private.attach ~parent:root ~child:branch ~index:0));
          ignore
            (expect_ok
               (Renderable.Private.attach ~parent:branch ~child:deep ~index:0));
          ignore (expect_ok (Renderable.Private.attach ~parent:root ~child:sibling ~index:1));
          equal bool true
            (match Renderable.find_descendant_by_id root "target" with
            | Some found -> found == deep
            | None -> false);
          Renderer.destroy renderer);
      test "nested coordinates include ancestor layout and translation"
        (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:10l ~height:8l ()) in
          let context = Renderer.context renderer in
          let root = Renderer.root renderer in
          let parent = make_child context ~id:"parent" () in
          let child = make_child context ~id:"child" () in
          ignore (expect_ok (Renderable.set_width parent (Core.Yoga.Point 4.0)));
          ignore (expect_ok (Renderable.set_height parent (Core.Yoga.Point 3.0)));
          ignore (expect_ok (Renderable.set_width child (Core.Yoga.Point 2.0)));
          ignore (expect_ok (Renderable.set_height child (Core.Yoga.Point 1.0)));
          ignore
            (expect_ok
               (Renderable.set_position child ~edge:Core.Yoga.Left
                  (Core.Yoga.Point 2.0)));
          ignore (expect_ok (Renderable.set_translate_x parent 1.0));
          ignore (expect_ok (Renderable.set_translate_y child 0.5));
          ignore (expect_ok (Renderable.Private.attach ~parent:root ~child:parent ~index:0));
          ignore (expect_ok (Renderable.Private.attach ~parent ~child ~index:0));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          equal (float 0.0001) 1.0 (Renderable.x parent);
          equal (float 0.0001) 3.0 (Renderable.x child);
          equal (float 0.0001) 0.5 (Renderable.y child);
          equal (float 0.0001) 3.0 (Renderable.screen_x child);
          ignore (expect_ok (Renderable.set_translate_x parent 2.0));
          equal (float 0.0001) 4.0 (Renderable.screen_x child);
          Renderer.destroy renderer);
      test "layout invalidation remains separate from render-list revision"
        (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:8l ~height:4l ()) in
          let context = Renderer.context renderer in
          let child = make_child context () in
          let before_layout = expect_ok (Context.layout_generation context) in
          let before_revision =
            expect_ok (Context.render_list_revision context)
          in
          ignore (expect_ok (Renderable.Private.attach ~parent:(Renderer.root renderer)
                               ~child ~index:0));
          let after_revision =
            expect_ok (Context.render_list_revision context)
          in
          equal bool true (Int64.compare after_revision before_revision > 0);
          ignore (expect_ok (Renderer.render renderer ~force:true));
          let after_layout = expect_ok (Context.layout_generation context) in
          equal bool true (Int64.compare after_layout before_layout > 0);
          let stable_revision =
            expect_ok (Context.render_list_revision context)
          in
          ignore (expect_ok (Renderer.render renderer ~force:true));
          equal int64 after_layout
            (expect_ok (Context.layout_generation context));
          equal int64 stable_revision
            (expect_ok (Context.render_list_revision context));
          Renderer.destroy renderer);
      test "filtered children retain z-order rather than callback order"
        (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:8l ~height:4l ()) in
          let context = Renderer.context renderer in
          let root = Renderer.root renderer in
          let seen = ref [] in
          let child_behavior =
            Renderable.Private.make_behavior
              ~on_update:(fun renderable _ ->
                seen := Renderable.id renderable :: !seen)
              ()
          in
          let parent_behavior =
            Renderable.Private.make_behavior
              ~visible_children:(fun renderable ->
                List.rev (Renderable.children renderable))
              ~filters_children:true ()
          in
          let parent = make_child context ~behavior:parent_behavior () in
          let first = make_child context ~behavior:child_behavior ~id:"first" () in
          let second = make_child context ~behavior:child_behavior ~id:"second" () in
          ignore (expect_ok (Renderable.set_z_index second (-1)));
          ignore (expect_ok (Renderable.Private.attach ~parent:root ~child:parent ~index:0));
          ignore (expect_ok (Renderable.Private.attach ~parent ~child:first ~index:0));
          ignore (expect_ok (Renderable.Private.attach ~parent ~child:second ~index:1));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          (match !seen with
          | "first" :: "second" :: _ -> ()
          | "second" :: "first" :: _ -> fail "filtered traversal ignored z-order"
          | _ -> fail "filtered traversal did not visit both children");
          Renderer.destroy renderer);
      test "a render request during a frame remains pending"
        (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:8l ~height:4l ()) in
          let context = Renderer.context renderer in
          let requested = ref false in
          let behavior =
            Renderable.Private.make_behavior
              ~updates_each_frame:true
              ~on_update:(fun renderable _ ->
                if not !requested then begin
                  requested := true;
                  ignore (Renderable.request_render renderable)
                end)
              ()
          in
          let child = make_child context ~behavior () in
          ignore
            (expect_ok
               (Renderable.Private.attach ~parent:(Renderer.root renderer)
                  ~child ~index:0));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          equal bool true (expect_ok (Context.has_pending_render context));
          Renderer.destroy renderer);
      test "resize-triggered destruction prevents command generation"
        (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:8l ~height:4l ()) in
          let context = Renderer.context renderer in
          let destroyed = ref None in
          let rendered = ref false in
          let behavior =
            Renderable.Private.make_behavior
              ~on_resize:(fun renderable ~width:_ ~height:_ ->
                Renderable.destroy renderable)
              ~render_self:(fun _ _ _ ->
                rendered := true;
                Ok ())
              ()
          in
          let child = make_child context ~behavior () in
          destroyed := Some child;
          ignore (expect_ok (Renderable.set_width child (Core.Yoga.Point 2.0)));
          ignore
            (expect_ok
               (Renderable.Private.attach ~parent:(Renderer.root renderer)
                  ~child ~index:0));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          equal bool true
            (match !destroyed with
            | Some renderable -> Renderable.is_destroyed renderable
            | None -> false);
          equal bool false !rendered;
          Renderer.destroy renderer);
      test "opacity and scissor drawing commands execute through native buffers"
        (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:8l ~height:4l ()) in
          let child = make_child (Renderer.context renderer) () in
          ignore (expect_ok (Renderable.set_opacity child 0.5));
          ignore
            (expect_ok
               (Renderable.Private.attach ~parent:(Renderer.root renderer)
                  ~child ~index:0));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          Renderer.destroy renderer);
      test "overflow scissor clips descendants in the retained hit grid"
        (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:8l ~height:4l ()) in
          let context = Renderer.context renderer in
          let parent = make_child context ~id:"clipped-parent" () in
          let child = make_child context ~id:"wide-child" () in
          ignore (expect_ok (Renderable.set_width parent (Core.Yoga.Point 4.0)));
          ignore (expect_ok (Renderable.set_height parent (Core.Yoga.Point 2.0)));
          ignore (expect_ok (Renderable.set_overflow parent Core.Yoga.Overflow_hidden));
          ignore (expect_ok (Renderable.set_width child (Core.Yoga.Point 8.0)));
          ignore (expect_ok (Renderable.set_height child (Core.Yoga.Point 2.0)));
          ignore (expect_ok (Renderable.set_flex_shrink child (Some 0.0)));
          ignore
            (expect_ok
               (Renderable.Private.attach ~parent:(Renderer.root renderer)
                  ~child:parent ~index:0));
          ignore
            (expect_ok
               (Renderable.Private.attach ~parent ~child ~index:0));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          equal bool true
            (match expect_ok (Renderer.hit_test renderer ~x:1 ~y:1) with
            | Some target -> target == child
            | None -> false);
          equal bool true
            (Option.is_none (expect_ok (Renderer.hit_test renderer ~x:5 ~y:1)));
          Renderer.destroy renderer);
      test "focus, visibility, detach, and destruction preserve reference lifecycle order"
        (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:8l ~height:4l ()) in
          let context = Renderer.context renderer in
          let root = Renderer.root renderer in
          let child = make_child context ~id:"focused" () in
          ignore (expect_ok (Renderable.set_focusable child true));
          ignore (expect_ok (Renderable.Private.attach ~parent:root ~child ~index:0));
          let destroyed_saw_parent = ref false in
          let destroyed_saw_flag = ref false in
          let blurred = ref 0 in
          ignore
            (expect_ok
               (Renderable.on_destroyed child (fun () ->
                    destroyed_saw_parent := Option.is_some (Renderable.parent child);
                    destroyed_saw_flag := Renderable.is_destroyed child)));
          ignore
            (expect_ok (Renderable.on_blurred child (fun () -> blurred := !blurred + 1)));
          ignore (expect_ok (Renderable.focus child));
          equal int (Renderable.num child)
            (Option.value (expect_ok (Context.focused_num context)) ~default:(-1));
          equal bool true (Renderable.has_focused_descendant root);
          ignore (expect_ok (Renderable.Private.detach ~parent:root ~child));
          equal bool true (Renderable.focused child);
          equal int (Renderable.num child)
            (Option.value (expect_ok (Context.focused_num context)) ~default:(-1));
          equal bool true (Renderable.has_focused_descendant root);
          ignore
            (expect_ok
               (Renderable.Private.attach ~parent:root ~child ~index:0));
          Renderable.destroy child;
          equal bool true !destroyed_saw_parent;
          equal bool true !destroyed_saw_flag;
          equal int 1 !blurred;
          equal bool true
            (Option.is_none (expect_ok (Context.focused_num context)));
          equal bool true (Renderable.has_focused_descendant root);
          Renderer.destroy renderer);
      test "hiding a focused renderable blurs it without restoring focus"
        (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:8l ~height:4l ()) in
          let context = Renderer.context renderer in
          let child = make_child context () in
          ignore (expect_ok (Renderable.set_focusable child true));
          ignore
            (expect_ok
               (Renderable.Private.attach ~parent:(Renderer.root renderer)
                  ~child ~index:0));
          ignore (expect_ok (Renderable.focus child));
          ignore (expect_ok (Renderable.set_visible child false));
          equal bool false (Renderable.focused child);
          equal bool true
            (Option.is_none (expect_ok (Context.focused_num context)));
          ignore (expect_ok (Renderable.set_visible child true));
          equal bool false (Renderable.focused child);
          Renderer.destroy renderer);
      test "live-count transitions reach the root scheduling boundary"
        (fun () ->
          let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:8l ~height:4l ()) in
          let context = Renderer.context renderer in
          let root = Renderer.root renderer in
          let child = make_child context () in
          ignore (expect_ok (Renderable.set_live child true));
          equal int 1 (Renderable.live_count child);
          ignore
            (expect_ok
               (Renderable.Private.attach ~parent:root ~child ~index:0));
          equal int 1 (Renderable.live_count root);
          equal int 1 (Context.Private.live_request_count context);
          ignore (expect_ok (Renderable.set_live child false));
          equal int 0 (Renderable.live_count root);
          equal int 0 (Context.Private.live_request_count context);
          Renderer.destroy renderer);
    ]
