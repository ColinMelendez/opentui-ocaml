open Windtrap

module Core = Opentui_core
module Clock = Core.Lib.Clock
module Eio_clock = Core.Platform.Eio_runtime.Eio_clock
module Mouse = Core.Lib.Mouse_decoder
module Renderable = Core.Renderable
module Renderer = Core.Renderer
module Renderables = Core.Renderables

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Core.Error.message error)

let close_eio_clock clock =
  match Eio_clock.close clock with
  | Ok () -> ()
  | Error error -> fail (Eio_clock.message error)

let modifiers = { Mouse.shift = false; alt = false; ctrl = false }

let mouse_event kind target =
  Renderable.Private.make_mouse_event ~kind ~button:0 ~x:0 ~y:0 ~modifiers
    ~scroll:None ~source:None ~target:(Some target) ~is_dragging:false

let send_mouse target kind =
  Renderable.Private.process_mouse_event target (mouse_event kind target)

let test_scrollbar_repeat () =
  let manual = Clock.manual () in
  let renderer =
    expect_ok
      (Renderer.create_with_clock ~output:Renderer.Output.Memory ~clock:(Clock.manual_clock manual) ~width:20l
         ~height:8l ())
  in
  let bar =
    expect_ok
      (Renderables.Scroll_bar.create (Renderer.context renderer)
         ~orientation:Renderables.Scroll_bar.Vertical ~show_arrows:true ())
  in
  ignore (expect_ok (Renderables.Scroll_bar.set_viewport_size bar 4.0));
  ignore (expect_ok (Renderables.Scroll_bar.set_scroll_size bar 20.0));
  let end_arrow = Renderables.Scroll_bar.end_arrow bar in
  send_mouse end_arrow Renderable.Down;
  equal (float 0.0001) 2.0 (Renderables.Scroll_bar.scroll_position bar);
  Clock.advance manual 0.499;
  equal (float 0.0001) 2.0 (Renderables.Scroll_bar.scroll_position bar);
  Clock.advance manual 0.001;
  equal (float 0.0001) 4.0 (Renderables.Scroll_bar.scroll_position bar);
  Clock.advance manual 0.199;
  equal (float 0.0001) 4.0 (Renderables.Scroll_bar.scroll_position bar);
  Clock.advance manual 0.001;
  equal (float 0.0001) 5.0 (Renderables.Scroll_bar.scroll_position bar);
  send_mouse end_arrow Renderable.Up;
  Clock.advance manual 1.0;
  equal (float 0.0001) 5.0 (Renderables.Scroll_bar.scroll_position bar);
  send_mouse end_arrow Renderable.Down;
  send_mouse end_arrow Renderable.Down;
  Clock.advance manual 0.5;
  equal (float 0.0001) 11.0 (Renderables.Scroll_bar.scroll_position bar);
  ignore (expect_ok (Renderables.Scroll_bar.set_show_arrows bar false));
  Clock.advance manual 1.0;
  equal (float 0.0001) 11.0 (Renderables.Scroll_bar.scroll_position bar);
  Renderables.Scroll_bar.destroy bar;
  Clock.advance manual 1.0;
  Renderer.destroy renderer

let test_scrollbar_without_clock_keeps_immediate_action () =
  let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:20l ~height:8l ()) in
  let bar =
    expect_ok
      (Renderables.Scroll_bar.create (Renderer.context renderer)
         ~orientation:Renderables.Scroll_bar.Vertical ~show_arrows:true ())
  in
  ignore (expect_ok (Renderables.Scroll_bar.set_viewport_size bar 4.0));
  ignore (expect_ok (Renderables.Scroll_bar.set_scroll_size bar 20.0));
  send_mouse (Renderables.Scroll_bar.end_arrow bar) Renderable.Down;
  equal (float 0.0001) 2.0 (Renderables.Scroll_bar.scroll_position bar);
  Renderables.Scroll_bar.destroy bar;
  Renderer.destroy renderer

let mouse kind ~x ~y =
  Core.Lib.Stdin_parser.Mouse
    {
      raw = Bytes.empty;
      encoding = Mouse.Sgr;
      event =
        {
          Mouse.kind;
          button = 0;
          x;
          y;
          modifiers;
          scroll = None;
        };
    }

let test_scrollbox_auto_scroll_keeps_other_live_owner () =
  let renderer = expect_ok (Renderer.create ~output:Renderer.Output.Memory ~width:20l ~height:8l ()) in
  let box =
    expect_ok
      (Renderables.Scroll_box.create (Renderer.context renderer) ~scroll_y:true
         ~width:(Core.Yoga.Point 10.0) ~height:(Core.Yoga.Point 4.0) ())
  in
  let text =
    expect_ok
      (Renderables.Text_buffer_renderable.create (Renderer.context renderer)
         ~selectable:true ())
  in
  let text_node = Renderables.Text_buffer_renderable.as_renderable text in
  ignore (expect_ok (Renderable.set_width text_node (Core.Yoga.Point 10.0)));
  ignore (expect_ok (Renderable.set_height text_node (Core.Yoga.Point 20.0)));
  ignore
    (expect_ok
       (Renderables.Text_buffer_renderable.set_text text
          "0123456789\n0123456789\n0123456789\n0123456789\n0123456789"));
  ignore (expect_ok (Renderables.Scroll_box.add box text_node));
  ignore
    (expect_ok
       (Core.Layout_children.add (Renderer.children renderer)
          (Renderables.Scroll_box.as_renderable box)));
  ignore (expect_ok (Renderer.render renderer ~force:true));
  ignore (expect_ok (Renderer.render renderer ~force:true));
  ignore (expect_ok (Renderer.request_live renderer));
  equal int 1 (expect_ok (Renderer.live_request_count renderer));
  equal bool false (Renderable.live (Renderables.Scroll_box.as_renderable box));
  let selection_events = ref 0 in
  ignore
    (expect_ok
       (Renderer.on_selection renderer (fun _ -> incr selection_events)));
  ignore (expect_ok (Renderer.handle_input renderer (mouse Mouse.Down ~x:1 ~y:3)));
  ignore (expect_ok (Renderer.handle_input renderer (mouse Mouse.Drag ~x:1 ~y:4)));
  let first_live_count = expect_ok (Renderer.live_request_count renderer) in
  if not (Int.equal first_live_count 2) then
    fail
      (Printf.sprintf "initial edge drag did not acquire lease: %d content=%g viewport=%g events=%d"
         first_live_count (Renderables.Scroll_box.scroll_height box)
         (Renderables.Scroll_box.viewport_height box) !selection_events);
  equal bool false (Renderable.live (Renderables.Scroll_box.as_renderable box));
  let before_events = !selection_events in
  let before_scroll = Renderables.Scroll_box.scroll_top box in
  ignore (expect_ok (Renderer.render ~delta_time:0.5 renderer ~force:true));
  equal bool true (Renderables.Scroll_box.scroll_top box > before_scroll);
  equal bool true (!selection_events > before_events);
  ignore (expect_ok (Renderer.handle_input renderer (mouse Mouse.Up ~x:1 ~y:4)));
  equal int 1 (expect_ok (Renderer.live_request_count renderer));
  equal bool false (Renderable.live (Renderables.Scroll_box.as_renderable box));
  ignore (expect_ok (Renderer.clear_selection renderer));
  equal int 1 (expect_ok (Renderer.live_request_count renderer));
  Renderables.Scroll_box.destroy box;
  equal int 1 (expect_ok (Renderer.live_request_count renderer));
  ignore (expect_ok (Renderer.drop_live renderer));
  equal int 0 (expect_ok (Renderer.live_request_count renderer));
  Renderables.Text_buffer_renderable.destroy text;
  Renderer.destroy renderer

let test_eio_theme_waiter_and_refresh_coalescing () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let mono_clock = Eio.Stdenv.mono_clock env in
  let eio_clock = Eio_clock.create ~sw ~mono_clock in
  let renderer =
    expect_ok
      (Renderer.create_with_clock ~output:Renderer.Output.Memory ~clock:(Eio_clock.lib_clock eio_clock)
         ~width:12l ~height:4l ())
  in
  let owner_domain = (Domain.self () :> int) in
  let waiter_result, resolve_waiter = Eio.Promise.create () in
  let callback_domain = ref None in
  let callback_value = ref None in
  ignore
    (expect_ok
       (Renderer.wait_for_theme_mode renderer ~timeout_ms:20
          ~on_result:(fun value ->
            callback_domain := Some (Domain.self () :> int);
            callback_value := Some value;
            Eio.Promise.resolve resolve_waiter ())));
  (match
     Eio.Fiber.first
       (fun () ->
         Eio.Promise.await waiter_result;
         `Waiter)
       (fun () ->
         Eio.Time.Mono.sleep mono_clock 0.2;
         `Bound)
   with
  | `Waiter -> ()
  | `Bound -> fail "Eio theme waiter exceeded its bounded test window");
  (match !callback_domain with
  | Some domain -> equal int owner_domain domain
  | None -> fail "Eio theme waiter did not report an owner domain");
  (match !callback_value with
  | Some None -> ()
  | Some (Some _) -> fail "theme waiter completed with an unexpected mode"
  | None -> fail "Eio theme waiter callback did not run");
  ignore (expect_ok (Renderer.request_theme_query renderer));
  ignore (expect_ok (Renderer.request_theme_query renderer));
  (match Renderer.theme_query renderer with
  | Some _ -> ()
  | None -> fail "first theme query request was not exposed");
  (match Renderer.theme_query renderer with
  | None -> ()
  | Some _ -> fail "theme query exposure was not coalesced");
  Eio.Time.Mono.sleep mono_clock 0.05;
  ignore (expect_ok (Renderer.request_theme_query renderer));
  (match Renderer.theme_query renderer with
  | None -> ()
  | Some _ -> fail "refresh-window theme query was not coalesced");
  Eio.Time.Mono.sleep mono_clock 0.25;
  ignore (expect_ok (Renderer.request_theme_query renderer));
  (match Renderer.theme_query renderer with
  | Some _ -> ()
  | None -> fail "theme query did not reopen after the refresh window");
  Renderer.destroy renderer;
  close_eio_clock eio_clock

let () =
  run "opentui-core-scheduler-consumers"
    [ test "scrollbar repeat follows the clock cadence and cancellation"
        test_scrollbar_repeat;
      test "clockless scrollbar performs only its immediate step"
        test_scrollbar_without_clock_keeps_immediate_action;
      test "scrollbox auto-scroll releases only its live contribution"
        test_scrollbox_auto_scroll_keeps_other_live_owner;
      test "Eio theme waiters time out on owner domain and refresh requests coalesce"
        test_eio_theme_waiter_and_refresh_coalescing ]
