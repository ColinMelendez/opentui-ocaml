open Windtrap

module Renderer = Opentui_core.Renderer
module Context = Opentui_core.Render_context
module Subscription = Opentui_core.Event_subscription

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Opentui_core.Error.message error)

let expect_error expected result =
  match result with
  | Ok _ -> fail "expected an error"
  | Error actual ->
      equal bool true
        (match expected, actual with
        | Opentui_core.Error.Closed, Opentui_core.Error.Closed -> true
        | _ -> false)

let () =
  run "opentui-core-renderer-context"
    [
      test "context observes renderer-owned dimensions and frame identity" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:2l ~height:1l) in
          let context = Renderer.context renderer in
          equal int32 2l (expect_ok (Context.width context));
          equal int32 1l (expect_ok (Context.height context));
          equal bool true (Context.same_owner context context);
          equal int64 0L (expect_ok (Context.frame_id context));
          equal bool false (expect_ok (Context.has_pending_render context));
          ignore (expect_ok (Context.request_render context));
          ignore (expect_ok (Context.request_render context));
          equal bool true (expect_ok (Context.has_pending_render context));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          equal int64 1L (expect_ok (Context.frame_id context));
          equal bool false (expect_ok (Context.has_pending_render context));
          ignore (expect_ok (Renderer.resize renderer ~width:3l ~height:2l));
          equal int32 3l (expect_ok (Context.width context));
          equal int32 2l (expect_ok (Context.height context));
          equal bool true (expect_ok (Renderer.has_pending_render renderer));
          Renderer.destroy renderer);
      test "renderer and context registrations share one event source" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:2l ~height:1l) in
          let context = Renderer.context renderer in
          let events = ref [] in
          ignore
            (expect_ok
               (Context.on_resize context (fun _ -> events := "context-resize" :: !events)));
          ignore
            (expect_ok
               (Renderer.on_resize renderer (fun _ -> events := "renderer-resize" :: !events)));
          ignore
            (expect_ok
               (Context.on_frame context (fun _ -> events := "context-frame" :: !events)));
          ignore
            (expect_ok
               (Renderer.on_frame renderer (fun _ -> events := "renderer-frame" :: !events)));
          ignore (expect_ok (Renderer.resize renderer ~width:3l ~height:2l));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          equal string "context-resize,renderer-resize,context-frame,renderer-frame"
            (String.concat "," (List.rev !events));
          Renderer.destroy renderer);
      test "resize subscriptions preserve prepend, snapshot, and once semantics" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:2l ~height:1l) in
          let context = Renderer.context renderer in
          let events = ref [] in
          let second = ref None in
          ignore
            (expect_ok
               (Context.on_resize context (fun _ ->
                    events := "first" :: !events;
                    match !second with
                    | None -> ()
                    | Some subscription -> Subscription.cancel subscription)));
          second :=
            Some
              (expect_ok
                 (Context.on_resize context (fun _ -> events := "second" :: !events)));
          ignore
            (expect_ok
               (Context.prepend_resize context (fun _ -> events := "prepended" :: !events)));
          ignore
            (expect_ok
               (Context.once_resize context (fun _ -> events := "once" :: !events)));
          ignore (expect_ok (Renderer.resize renderer ~width:3l ~height:1l));
          ignore (expect_ok (Renderer.resize renderer ~width:4l ~height:1l));
          equal string "prepended,first,second,once,prepended,first"
            (String.concat "," (List.rev !events));
          Renderer.destroy renderer);
      test "renderer contexts have distinct owner identities" (fun () ->
          let left = expect_ok (Renderer.create ~width:1l ~height:1l) in
          let right = expect_ok (Renderer.create ~width:1l ~height:1l) in
          equal bool true
            (Context.same_owner (Renderer.context left) (Renderer.context left));
          equal bool false
            (Context.same_owner (Renderer.context left) (Renderer.context right));
          Renderer.destroy left;
          Renderer.destroy right);
      test "borrowed buffer values survive resize and close with their renderer" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:2l ~height:1l) in
          let buffer = expect_ok (Renderer.next_buffer renderer) in
          let same_buffer = expect_ok (Renderer.next_buffer renderer) in
          equal bool true (buffer == same_buffer);
          ignore (expect_ok (Renderer.resize renderer ~width:4l ~height:3l));
          equal int32 4l (expect_ok (Opentui_core.Buffer.width buffer));
          equal int32 3l (expect_ok (Opentui_core.Buffer.height buffer));
          Renderer.destroy renderer;
          expect_error Opentui_core.Error.Closed
            (Renderer.next_buffer renderer);
          (match Opentui_core.Buffer.width buffer with
          | Error Opentui_core.Error.Closed -> ()
          | Error error -> fail (Opentui_core.Error.message error)
          | Ok _ -> fail "a borrowed buffer remained open after renderer destroy"));
      test "destroy is idempotent and closes the shared context" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:1l ~height:1l) in
          let context = Renderer.context renderer in
          Renderer.destroy renderer;
          Renderer.destroy renderer;
          equal bool true (Renderer.is_destroyed renderer);
          expect_error Opentui_core.Error.Closed (Context.width context);
          expect_error Opentui_core.Error.Closed
            (Context.request_render context);
          (match Context.on_frame context ignore with
          | Error Opentui_core.Error.Closed -> ()
          | Error error -> fail (Opentui_core.Error.message error)
          | Ok _ -> fail "closed context accepted a new event registration"));
    ]
