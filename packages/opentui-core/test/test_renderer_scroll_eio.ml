open Windtrap

module Core = Opentui_core
module Eio_clock = Core.Platform.Eio_runtime.Eio_clock
module Output_flow = Core.Platform.Eio_runtime.Output_flow
module Renderer = Core.Renderer
module Renderable = Core.Renderable
module Renderables = Core.Renderables
module Scheduler = Core.Platform.Eio_runtime.Renderer_scheduler

type trace_event =
  | Pre_render of {
      at : float;
      delta : float;
      scroll_top : float;
      translation_y : float;
      content_height : float;
    }
  | Output_frame of { at : float; chunks : int; bytes : int }
  | Output_complete of { at : float }
  | Sink_write of { at : float; bytes : int }
  | Renderer_frame of { at : float; frame_id : int64 }

type sink_state = {
  clock : Eio_clock.t;
  trace : trace_event list ref;
}

module Recording_sink = struct
  type t = sink_state

  let single_write sink buffers =
    let bytes = Cstruct.lenv buffers in
    sink.trace := Sink_write { at = Eio_clock.now sink.clock; bytes } :: !(sink.trace);
    bytes

  let copy sink ~src = Eio.Flow.Pi.simple_copy ~single_write sink ~src
end

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Core.Error.message error)

let expect_scheduler result =
  match result with
  | Ok value -> value
  | Error error -> fail (Scheduler.message error)

let make_row context text =
  let row =
    expect_ok
      (Renderables.Text.create context
         ~content:(Core.Lib.Styled_text.of_string text) ())
  in
  let renderable = Renderables.Text.as_renderable row in
  ignore (expect_ok (Renderable.set_width renderable (Core.Yoga.Point 10.0)));
  ignore (expect_ok (Renderable.set_height renderable (Core.Yoga.Point 1.0)));
  row, renderable

let attach renderer renderable =
  ignore
    (expect_ok
       (Core.Layout_children.add (Renderer.children renderer) renderable))

let start_scheduler ~sw scheduler =
  let result, resolve_result = Eio.Promise.create () in
  Eio.Fiber.fork ~sw (fun () ->
      Eio.Promise.resolve resolve_result (Scheduler.run scheduler));
  Eio.Fiber.yield ();
  result

let trace_in_chronological_order trace = List.rev !trace

let event_summary = function
  | Pre_render { at; delta; scroll_top; translation_y; content_height } ->
      Printf.sprintf "pre@%.4f delta=%.4f top=%.2f translate=%.2f height=%.2f"
        at delta scroll_top translation_y content_height
  | Output_frame { at; chunks; bytes } ->
      Printf.sprintf "feed@%.4f chunks=%d bytes=%d" at chunks bytes
  | Output_complete { at } -> Printf.sprintf "feed-done@%.4f" at
  | Sink_write { at; bytes } -> Printf.sprintf "write@%.4f bytes=%d" at bytes
  | Renderer_frame { at; frame_id } ->
      Printf.sprintf "frame@%.4f id=%Ld" at frame_id

let append trace event =
  trace := event :: !trace;
  match Sys.getenv_opt "OPENTUI_SCROLL_TRACE" with
  | Some value when String.equal value "1" ->
      Printf.eprintf "renderer scroll event: %s\n%!" (event_summary event)
  | Some _ | None -> ()

let trace_summary trace =
  trace_in_chronological_order trace
  |> List.map event_summary |> String.concat " | "

let await_promise ~mono_clock ~trace ~label promise =
  match
    Eio.Fiber.first
      (fun () ->
        Eio.Promise.await promise;
        `Ready)
      (fun () ->
        Eio.Time.Mono.sleep mono_clock 1.0;
        `Timeout)
  with
  | `Ready -> ()
  | `Timeout ->
      fail
        (Printf.sprintf "timed out waiting for %s; trace=%s" label
           (trace_summary trace))

let maybe_print_trace trace =
  match Sys.getenv_opt "OPENTUI_SCROLL_TRACE" with
  | Some value when String.equal value "1" ->
      Printf.eprintf "renderer scroll trace: %s\n%!" (trace_summary trace)
  | Some _ | None -> ()

let () =
  run "opentui-core-renderer-scroll-eio"
    [
      test
        "Eio scrolling keeps frame output ordered and paced after one scroll"
        (fun () ->
          Eio_main.run @@ fun env ->
          Eio.Switch.run @@ fun sw ->
          let mono_clock = Eio.Stdenv.mono_clock env in
          let clock = Eio_clock.create ~sw ~mono_clock in
          let trace = ref [] in
          let sink_state = { clock; trace } in
          let sink_resource =
            Eio.Resource.T
              (sink_state, Eio.Flow.Pi.sink (module Recording_sink))
          in
          let output = Output_flow.create ~sink:sink_resource in
          let output_sink =
            Renderer.Output.sink ~write_frame:(fun chunks ->
                let bytes =
                  List.fold_left
                    (fun total chunk -> total + Bytes.length chunk) 0 chunks
                in
                append trace
                  (Output_frame
                     {
                       at = Eio_clock.now clock;
                       chunks = List.length chunks;
                       bytes;
                     });
                let result =
                  match Output_flow.write_frame output chunks with
                  | Ok () -> Ok ()
                  | Error error ->
                      Error (Core.Error.Output (Output_flow.message error))
                in
                append trace (Output_complete { at = Eio_clock.now clock });
                result)
          in
          let renderer =
            expect_ok
              (Renderer.create_with_clock
                 ~output:(Renderer.Output.Sink output_sink)
                 ~clock:(Eio_clock.lib_clock clock) ~width:10l ~height:3l ())
          in
          let box =
            expect_ok
              (Renderables.Scroll_box.create (Renderer.context renderer)
                 ~scroll_y:true ~viewport_culling:false
                 ~width:(Core.Yoga.Point 10.0)
                 ~height:(Core.Yoga.Point 3.0) ())
          in
          ignore
            (expect_ok
               (Renderables.Scroll_bar.set_visible
                  (Renderables.Scroll_box.vertical_scrollbar box) false));
          List.iter
            (fun text ->
              let row, renderable = make_row (Renderer.context renderer) text in
              ignore (expect_ok (Renderables.Scroll_box.add box renderable));
              ignore row)
            [ "Aaaaaaaaaa"; "Bbbbbbbbbb"; "Cccccccccc"; "Dddddddddd";
              "Eeeeeeeeee"; "Ffffffffff"; "Gggggggggg" ];
          attach renderer (Renderables.Scroll_box.as_renderable box);
          let live_started = ref None in
          let live_pre_times = ref [] in
          ignore
            (expect_ok
               (Renderer.attach_pre_render renderer (fun delta ->
                    let at = Eio_clock.now clock in
                    (match !live_started with
                     | Some _ -> live_pre_times := at :: !live_pre_times
                     | None -> ());
                    append trace
                      (Pre_render
                         {
                           at;
                           delta;
                           scroll_top = Renderables.Scroll_box.scroll_top box;
                           translation_y =
                             Renderable.translate_y
                               (Renderables.Scroll_box.content box);
                           content_height =
                             Renderables.Scroll_box.scroll_height box;
                         }))));
          let frame_count = ref 0 in
          let scrolled = ref false in
          let scroll_frame_resolved = ref false in
          let paced_frames_resolved = ref false in
          let initial_frame, resolve_initial = Eio.Promise.create () in
          let settled_frame, resolve_settled = Eio.Promise.create () in
          let scroll_frame, resolve_scroll = Eio.Promise.create () in
          let paced_frames, resolve_paced = Eio.Promise.create () in
          ignore
            (expect_ok
               (Renderer.on_frame renderer (fun event ->
                    incr frame_count;
                    append trace
                      (Renderer_frame
                         {
                           at = Eio_clock.now clock;
                           frame_id = event.frame_id;
                         });
                    if Int.equal !frame_count 1 then
                      Eio.Promise.resolve resolve_initial ()
                    else if Int.equal !frame_count 2 then
                      Eio.Promise.resolve resolve_settled ()
                    else if !scrolled && not !scroll_frame_resolved then begin
                      scroll_frame_resolved := true;
                      Eio.Promise.resolve resolve_scroll ()
                    end;
                    if !scrolled && Int.compare !frame_count 5 >= 0
                       && not !paced_frames_resolved then begin
                      paced_frames_resolved := true;
                      Eio.Promise.resolve resolve_paced ()
                    end)));
          let scheduler =
            expect_scheduler
              (Scheduler.create ~sw ~clock ~renderer
                 ~target_frames_per_second:60 ~max_frames_per_second:60 ())
          in
          ignore (expect_ok (Renderer.request_render renderer));
          let scheduler_result = start_scheduler ~sw scheduler in
          await_promise ~mono_clock ~trace ~label:"initial frame" initial_frame;
          ignore (expect_ok (Renderer.request_render renderer));
          await_promise ~mono_clock ~trace ~label:"settled frame" settled_frame;
          let initial_height = Renderables.Scroll_box.scroll_height box in
          let initial_translation =
            Renderable.translate_y (Renderables.Scroll_box.content box)
          in
          scrolled := true;
          live_started := Some (Eio_clock.now clock);
          ignore (expect_ok (Renderer.request_live renderer));
          ignore
            (expect_ok
               (Renderables.Scroll_box.scroll_by box ~dx:0.0 ~dy:1.0));
          await_promise ~mono_clock ~trace ~label:"scroll frame" scroll_frame;
          await_promise ~mono_clock ~trace ~label:"paced frames" paced_frames;
          let final_height = Renderables.Scroll_box.scroll_height box in
          let final_translation =
            Renderable.translate_y (Renderables.Scroll_box.content box)
          in
          ignore (expect_ok (Renderer.drop_live renderer));
          ignore (expect_scheduler (Scheduler.close scheduler));
          (match Eio.Promise.await scheduler_result with
           | Ok () -> ()
           | Error error -> fail (Scheduler.message error));
          let events = trace_in_chronological_order trace in
          maybe_print_trace trace;
          if Int.compare !frame_count 2 < 0 then
            fail "the Eio scheduler produced fewer than two rendered frames";
          if not (Float.equal (Renderables.Scroll_box.scroll_top box) 1.0) then
            fail
              (Printf.sprintf
                 "scroll position was not applied: %.3f height=%.3f viewport=%.3f translation=%.3f trace=%s"
                 (Renderables.Scroll_box.scroll_top box) final_height
                 (Renderables.Scroll_box.viewport_height box)
                 final_translation (trace_summary trace));
          if not (Float.equal final_translation (-1.0)) then
            fail
              (Printf.sprintf "content translation was not applied: %.3f"
                 final_translation);
          if not (Float.equal initial_translation 0.0) then
            fail
              (Printf.sprintf "initial content translation was %.3f"
                 initial_translation);
          let rendered_frames = ref 0 in
          let output_frames = ref 0 in
          let output_open = ref false in
          List.iter
            (function
              | Pre_render _ -> ()
              | Output_frame _ ->
                  incr output_frames;
                  if !output_open then
                    fail "a feed frame began before the prior frame completed";
                  output_open := true
              | Output_complete _ ->
                  if not !output_open then
                    fail "a feed frame completed without a start";
                  output_open := false
              | Sink_write _ ->
                  if not !output_open then
                    fail "an Eio sink write escaped its feed frame"
              | Renderer_frame _ ->
                  if !output_open then
                    fail "renderer frame completed before output finished";
                  incr rendered_frames)
            events;
          if !output_open then fail "the final feed frame was not completed";
          equal int !frame_count !rendered_frames;
          if Int.compare !output_frames !rendered_frames < 0 then
            fail "the feed produced fewer frame boundaries than rendered frames";
          let pre_times =
            List.rev !live_pre_times
          in
          (match pre_times with
           | first :: second :: _ ->
               if Float.compare (second -. first) 0.010 < 0 then
                 fail
                   (Printf.sprintf
                      "live scheduler rendered too quickly: %.6f seconds"
                      (second -. first))
           | _ -> fail "the Eio scheduler produced too few pre-render samples");
          if Float.compare final_height initial_height < 0 then
            fail
              (Printf.sprintf
                 "ScrollBox content height shrank after translation: %.3f -> %.3f"
                 initial_height final_height);
          Renderer.destroy renderer;
          ignore (Eio_clock.close clock))
    ]
