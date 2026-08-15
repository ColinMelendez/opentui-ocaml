open Windtrap

module Core = Opentui_core
module Detection = Core.Lib.Terminal_capability_detection
module Renderer = Core.Renderer
module Context = Core.Render_context

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Core.Error.message error)

let response sequence =
  Core.Lib.Stdin_parser.Response
    { protocol = Core.Lib.Stdin_parser.Unknown; bytes = Bytes.of_string sequence }

let expect_pixel_resolution result ~width ~height =
  match result with
  | None -> fail "expected a pixel resolution"
  | Some actual ->
      equal int32 width actual.Detection.width;
      equal int32 height actual.Detection.height

let () =
  run "opentui-core-terminal-capabilities"
    [
      test "recognizes upstream capability response families" (fun () ->
          equal bool true (Detection.is_capability_response "\027[?1016;2$y");
          equal bool true (Detection.is_capability_response "\027[1;2R");
          equal bool true
            (Detection.is_capability_response "\027P>|kitty(0.40.1)\027\\");
          equal bool true
            (Detection.is_capability_response "\027P1+r4d73=2570312573\027\\");
          equal bool true
            (Detection.is_capability_response "\027P0+r4D73\027\\");
          equal bool true
            (Detection.is_capability_response "\027_Gi=1;OK\027\\");
          equal bool true (Detection.is_capability_response "\027[?31u");
          equal bool true (Detection.is_capability_response "\027[?62;22c");
          equal bool true
            (Detection.is_capability_response
               "\027]99;i=opentui-notifications:p=?;p=title\027\\");
          equal bool true
            (Detection.is_capability_response "\027]1337;Capabilities=T2NoH\007"));
      test "does not classify ordinary input or cursor reports as capabilities"
        (fun () ->
          equal bool false (Detection.is_capability_response "a");
          equal bool false (Detection.is_capability_response "\027[A");
          equal bool false (Detection.is_capability_response "\027[10;5R");
          equal bool false
            (Detection.is_capability_response "\027P1+r544e=787465726d\027\\");
          equal bool false
            (Detection.is_capability_response "\027]99;i=other:p=?;p=title\027\\"));
      test "parses bounded pixel resolution responses" (fun () ->
          equal bool true
            (Detection.is_pixel_resolution_response "\027[4;720;1280t");
          expect_pixel_resolution
            (Detection.parse_pixel_resolution "\027[4;720;1280t")
            ~width:1280l ~height:720l;
          expect_pixel_resolution
            (Detection.parse_pixel_resolution "prefix\027[4;0;0tsuffix")
            ~width:0l ~height:0l;
          equal bool false (Detection.is_pixel_resolution_response "\027[A");
          (match
             Detection.parse_pixel_resolution
               "\027[4;4294967295;4294967295t"
           with
          | None -> ()
          | Some _ -> fail "an oversized pixel resolution was accepted"));
      test "publishes processed capabilities through shared renderer events"
        (fun () ->
          let renderer = expect_ok (Renderer.create ~width:2l ~height:1l) in
          let context = Renderer.context renderer in
          let events = ref [] in
          ignore
            (expect_ok
               (Context.on_capabilities context (fun capabilities ->
                    events :=
                      ("context:" ^ capabilities.terminal.name) :: !events)));
          ignore
            (expect_ok
               (Renderer.on_capabilities renderer (fun capabilities ->
                    events :=
                      ("renderer:" ^ capabilities.terminal.name) :: !events)));
          let initial = expect_ok (Renderer.capabilities renderer) in
          (match initial with
          | None -> fail "renderer did not expose its initial capability snapshot"
          | Some _ -> ());
          (match expect_ok (Renderer.render renderer ~force:true) with
          | Renderer.Rendered -> ()
          | Renderer.Skipped -> fail "initial forced frame was skipped"
          | Renderer.Failed -> fail "initial forced frame failed");
          let handled =
            expect_ok
              (Renderer.handle_input renderer
                 (response "\027P>|kitty(0.42.2)\027\\"))
          in
          equal bool true handled;
          equal bool true (expect_ok (Renderer.has_pending_render renderer));
          equal string "context:kitty,renderer:kitty"
            (String.concat "," (List.rev !events));
          let capabilities = expect_ok (Context.capabilities context) in
          (match capabilities with
          | None -> fail "context lost the processed capability snapshot"
          | Some capabilities ->
              equal string "kitty" capabilities.terminal.name;
              equal string "0.42.2" capabilities.terminal.version);
          (match expect_ok (Renderer.render renderer ~force:false) with
          | Renderer.Rendered -> ()
          | Renderer.Skipped ->
              fail "capability update did not force the next native frame"
          | Renderer.Failed -> fail "forced capability frame failed");
          equal bool false (expect_ok (Renderer.has_pending_render renderer));
          Renderer.destroy renderer);
      test "capability responses are consumed without reaching key handlers"
        (fun () ->
          let renderer = expect_ok (Renderer.create ~width:1l ~height:1l) in
          let keypresses = ref 0 in
          ignore
            (expect_ok
               (Renderer.on_keypress renderer (fun _ -> incr keypresses)));
          equal bool true
            (expect_ok
               (Renderer.handle_input renderer (response "\027[?2027;2$y")));
          equal int 0 !keypresses;
          equal bool false
            (expect_ok
               (Renderer.handle_input renderer (response "not-a-response")));
          Renderer.destroy renderer);
      test "closed renderers reject capability access and subscriptions" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:1l ~height:1l) in
          let context = Renderer.context renderer in
          Renderer.destroy renderer;
          (match Renderer.capabilities renderer with
          | Error Core.Error.Closed -> ()
          | Error error -> fail (Core.Error.message error)
          | Ok _ -> fail "closed renderer exposed capabilities");
          (match Context.on_capabilities context ignore with
          | Error Core.Error.Closed -> ()
          | Error error -> fail (Core.Error.message error)
          | Ok _ -> fail "closed context accepted a capability subscription"));
    ]
