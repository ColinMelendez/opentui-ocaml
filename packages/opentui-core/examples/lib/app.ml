(* Minimal Eio terminal app harness for the opentui examples.

   Owns the parts of the reference `createCliRenderer` plumbing that the OCaml
   port expresses explicitly: a raw-mode terminal session, selectable terminal screen,
   a bounded input queue fed by one fiber and drained by a dispatch fiber, a
   renderer scheduler driving requested or live frames, and pre-render drivers
   for terminal-size polling and demo-owned animation. Each demo opts into
   continuous rendering when it matches the reference demo's explicit start
   behavior. *)

module O = Opentui_core
module Output = O.Platform.Eio_runtime.Output_flow
module Input_flow = O.Platform.Eio_runtime.Input_flow
module Clock = O.Lib.Clock
module Eio_clock = O.Platform.Eio_runtime.Eio_clock
module Dispatch = O.Platform.Eio_runtime.Dispatch
module Wakeup = O.Platform.Eio_runtime.Wakeup
module Scheduler = O.Platform.Eio_runtime.Renderer_scheduler
module Session = O.Platform.Eio_unix_runtime.Terminal_session
module Size_source = O.Platform.Eio_unix_runtime.Terminal_size_source
module Resize = O.Platform.Eio_unix_runtime.Resize_source
module Events = O.Lib.Event_queue
module Input = O.Lib.Input_coordinator
module Stdin_parser = O.Lib.Stdin_parser
module Capability_detection = O.Lib.Terminal_capability_detection
module Modes = O.Lib.Terminal_modes
module Size = O.Lib.Terminal_size

module Tty_source = struct
  type t = Eio_unix.Fd.t

  let read_methods = []

  let single_read fd destination =
    let bytes = Bytes.create (Cstruct.length destination) in
    Eio_unix.Fd.use_exn "read" fd (fun unix_fd ->
        Eio_unix.await_readable unix_fd;
        let count = Unix.read unix_fd bytes 0 (Bytes.length bytes) in
        if Int.equal count 0 then raise End_of_file;
        Cstruct.blit_from_bytes bytes 0 destination 0 count;
        count)
end

module Tty_sink = struct
  type t = Eio_unix.Fd.t

  let single_write fd buffers =
    let rec write_first = function
      | [] -> 0
      | buffer :: rest when Int.equal (Cstruct.length buffer) 0 ->
          write_first rest
      | buffer :: _ ->
          let bytes = Cstruct.to_bytes buffer in
          Eio_unix.Fd.use_exn "write" fd (fun unix_fd ->
              Eio_unix.await_writable unix_fd;
              Unix.single_write unix_fd bytes 0 (Bytes.length bytes))
    in
    write_first buffers

  let copy fd ~src = Eio.Flow.Pi.simple_copy ~single_write fd ~src
end

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> invalid_arg (O.Error.message error)

let expect_session result =
  match result with
  | Ok value -> value
  | Error error -> invalid_arg (Session.message error)

let expect_session_ok result =
  match result with
  | Ok () -> ()
  | Error error -> invalid_arg (Session.message error)

let expect_output_ok result =
  match result with
  | Ok () -> ()
  | Error error -> invalid_arg (Output.message error)

let expect_scheduler result =
  match result with
  | Ok value -> value
  | Error error -> invalid_arg (Scheduler.message error)

let expect_size result =
  match result with
  | Ok value -> value
  | Error error -> invalid_arg (Size_source.message error)

let expect_input result =
  match result with
  | Ok value -> value
  | Error error -> invalid_arg (Input_flow.message error)

let expect_resize result =
  match result with
  | Ok value -> value
  | Error error -> invalid_arg (Resize.message error)

let expect_events result =
  match result with
  | Ok value -> value
  | Error error -> invalid_arg (Events.message error)

(* Use the standard input/output streams as the terminal. Like the reference
   [createCliRenderer], the demo reads stdin and writes stdout; both are the
   controlling terminal when the demo runs interactively. The fds are wrapped
   in blocking mode so Eio's scheduler can poll them. *)
let open_tty ~sw () =
  let input = Eio_unix.Fd.of_unix ~sw ~blocking:true ~seekable:false ~close_unix:false Unix.stdin in
  let output = Eio_unix.Fd.of_unix ~sw ~blocking:true ~seekable:false ~close_unix:false Unix.stdout in
  input, output

let emit_to_queue queue wakeup (event : Input.event) =
  match Events.push queue (Events.Input event) with
  | Ok () -> Wakeup.notify wakeup; Input.Accepted
  | Error Events.Full -> Input.Full
  | Error Events.Invalid_capacity -> assert false

let capability_detection_context =
  {
    Stdin_parser.default_protocol_context with
    private_capability_replies_active = true;
    pixel_resolution_query_active = true;
    explicit_width_cpr_active = true;
  }

let capability_detection_finished_context =
  {
    capability_detection_context with
    private_capability_replies_active = false;
    pixel_resolution_query_active = false;
    explicit_width_cpr_active = false;
  }

let capability_detection_pixel_response_context =
  { capability_detection_context with pixel_resolution_query_active = false }

let update_capability_protocol_context input context ~queue ~wakeup =
  Input_flow.update_protocol_context input context
    ~emit:(emit_to_queue queue wakeup)

(* Pump the tty source through the coordinator into the bounded queue, then
   wait for SIGWINCH to enqueue resize events. *)
let pump_input input ~clock ~source ~queue ~wakeup =
  let rec read_loop () =
    match
      Input_flow.read_once input ~clock ~source ~emit:(emit_to_queue queue wakeup)
    with
    | Ok (Input_flow.Bytes_read _) ->
        Eio.Fiber.yield ();
        read_loop ()
    | Ok (Input_flow.Backpressured _) ->
        Eio.Fiber.yield ();
        read_loop ()
    | Ok Input_flow.End_of_input -> ()
    | Error error -> invalid_arg (Input_flow.message error)
  in
  read_loop ()

(* [Input_flow] deliberately exposes timeout delivery to its owner so the
   pure coordinator remains usable with runtimes other than Eio. The terminal
   harness owns that policy, so keep a small timer fiber beside the blocking
   reader. Without it a lone ESC remains buffered and is later reinterpreted
   as the prefix of the next key. *)
let pump_input_timeouts input ~clock ~queue ~wakeup =
  let delay = float_of_int (Input_flow.timeout_ms input) /. 1000.0 in
  let rec loop () =
    Eio.Time.Mono.sleep clock delay;
    (match
       Input_flow.fire_timeout input ~clock
         ~emit:(emit_to_queue queue wakeup)
     with
    | Ok _ -> loop ()
    | Error error -> invalid_arg (Input_flow.message error))
  in
  loop ()

let dispatch_handle renderer ~capability_detection_active ~on_pixel_resolution = function
  | Events.Resize size ->
      ignore
        (O.Renderer.resize renderer ~width:(Int32.of_int (Size.columns size))
           ~height:(Int32.of_int (Size.rows size)))
  | Events.Input
      (Stdin_parser.Response { bytes; _ } as event) ->
      ignore (O.Renderer.handle_input renderer event);
      if !capability_detection_active then
        if
          Capability_detection.is_pixel_resolution_response
            (Bytes.to_string bytes)
        then on_pixel_resolution ()
  | Events.Input event -> ignore (O.Renderer.handle_input renderer event)

let run ?(target_frames_per_second = 30) ?(max_frames_per_second = 60)
    ?(kitty_events = true) ?(screen = Modes.Alternate) ?(reserve_screen = false)
    ?(detect_terminal_capabilities = false) env ~init =
  Eio.Switch.run @@ fun sw ->
  let mono_clock = Eio.Stdenv.mono_clock env in
  let input_fd, output_fd = open_tty ~sw () in
  let tty_size = expect_size (Size_source.get input_fd) in
  let output =
    Output.create ~sink:(Eio.Resource.T (output_fd, Eio.Flow.Pi.sink (module Tty_sink)))
  in
  let session =
    expect_session
      (Session.create ~sw ~fd:input_fd ~output)
  in
  expect_session_ok (Session.enter session);
  expect_session_ok
    (Session.setup_output session ~screen ~bracketed_paste:true);
  if reserve_screen then
    expect_output_ok
      (Output.write output
         (Bytes.of_string
            (String.make (max 0 (Size.rows tty_size - 1)) '\n')));
  (match Output.set_cursor_visible output false with
  | Ok () -> ()
  | Error error -> invalid_arg (Output.message error));
  (match Output.set_mouse output ~movement:true with
  | Ok () -> ()
  | Error error -> invalid_arg (Output.message error));
  let clock = Eio_clock.create ~sw ~mono_clock in
  let renderer_output =
    O.Renderer.Output.sink ~write_frame:(fun chunks ->
        match Output.write_frame output chunks with
        | Ok () -> Ok ()
        | Error error -> Error (O.Error.Output (Output.message error)))
  in
  let input = expect_input (Input_flow.create ()) in
  let queue = expect_events (Events.create ~capacity:64 ()) in
  let wakeup = Wakeup.create () in
  let renderer =
    expect_ok
      (O.Renderer.create_with_clock
         ~output:(O.Renderer.Output.Sink renderer_output)
         ~clock:(Eio_clock.lib_clock clock)
         ~width:(Int32.of_int (Size.columns tty_size))
         ~height:(Int32.of_int (Size.rows tty_size)) ())
  in
  let set_mouse_protocol enabled =
    let result =
      if enabled then Output.set_mouse output ~movement:true
      else Output.disable_mouse output
    in
    match result with
    | Ok () ->
        Input_flow.reset_mouse_state input;
        Ok ()
    | Error error -> Error (O.Error.Output (Output.message error))
  in
  ignore (expect_ok (O.Renderer.set_mouse_protocol renderer set_mouse_protocol));
  expect_output_ok
    (Output.write output (Bytes.of_string O.Lib.Ansi.modify_other_keys_set));
  (* The output flow also emits a hide-cursor mode, but the renderer has its
     own presentation cursor state and may otherwise re-enable it on the
     first frame. *)
  ignore
    (expect_ok
       (O.Renderer.set_cursor_position renderer ~x:1l
          ~y:(if reserve_screen then Int32.of_int (Size.rows tty_size) else 1l)
          ~visible:false ()));
  (match O.Renderer.kitty_keyboard_push renderer ~events:kitty_events () with
  | bytes -> expect_output_ok (Output.write output bytes));
  (* The reference setup starts capability detection as part of terminal
     setup. This harness keeps terminal modes in [Session] and therefore
     starts only the native probe phase here, after its direct setup writes.
     The probe itself remains native so XTVERSION ordering, multiplexer
     wrapping, pending retries, and pixel-resolution querying stay aligned
     with the reference. *)
  let capability_detection_timer = ref None in
  let capability_context_retry_timer = ref None in
  let capability_detection_active = ref false in
  let cancel_capability_context_retry () =
    match !capability_context_retry_timer with
    | None -> ()
    | Some timer ->
        Clock.cancel (Eio_clock.lib_clock clock) timer;
        capability_context_retry_timer := None
  in
  let rec retry_capability_context context () =
    capability_context_retry_timer := None;
    match
      update_capability_protocol_context input context ~queue ~wakeup
    with
    | Input.Accepted -> ()
    | Input.Full ->
        (* The coordinator retains its pending event. Retry independently of
           input arrival so a full application queue cannot strand the
           context transition after the startup window expires. *)
        let timer =
          Clock.schedule (Eio_clock.lib_clock clock) ~delay:0.01
            (retry_capability_context context)
        in
        capability_context_retry_timer := Some timer
  in
  let schedule_capability_context context =
    cancel_capability_context_retry ();
    retry_capability_context context ()
  in
  let on_pixel_resolution () =
    if !capability_detection_active then
      schedule_capability_context capability_detection_pixel_response_context
  in
  if detect_terminal_capabilities then begin
    capability_detection_active := true;
    schedule_capability_context capability_detection_context;
    ignore (expect_ok (O.Renderer.start_capability_detection renderer));
    let timer =
      Clock.schedule (Eio_clock.lib_clock clock) ~delay:5.0 (fun () ->
          capability_detection_timer := None;
          capability_detection_active := false;
          schedule_capability_context capability_detection_finished_context)
    in
    capability_detection_timer := Some timer
  end;
  let resize =
    match Resize.create ~sw () with
    | Ok value -> value
    | Error _ -> invalid_arg (Resize.message (Resize.Already_installed))
  in
  (* The demo installs its retained tree and handlers before the scheduler
     starts consuming requests. [Dispatch.run] yields between bounded input
     batches, so a busy mouse stream cannot starve the scheduler. [exit] stops
     the scheduler so the harness can drain renderer output and restore the
     terminal session. *)
  let scheduler =
    expect_scheduler
      (Scheduler.create ~sw ~clock ~renderer ~target_frames_per_second
         ~max_frames_per_second ())
  in
  let exit () = ignore (Scheduler.close scheduler) in
  (* Besides SIGWINCH, poll the terminal size on each frame that is already
     being rendered. The resize signal path still requests a frame for
     on-demand demos when no live loop is active. *)
  let last_size = ref tty_size in
  ignore
    (expect_ok
       (O.Renderer.attach_pre_render renderer (fun _delta ->
            match Size_source.get input_fd with
            | Ok size when not (Size.equal size !last_size) ->
                last_size := size;
                ignore
                  (O.Renderer.resize renderer
                     ~width:(Int32.of_int (Size.columns size))
                     ~height:(Int32.of_int (Size.rows size)))
            | Ok _ | Error _ -> ())));
  let cleanup () =
    (* Cleanup is deliberately best effort here: it also runs while unwinding
       an exception from demo initialization or a renderer callback, so a
       failed cleanup operation must not prevent the terminal session from
       being restored. *)
    ignore (Scheduler.close scheduler);
    cancel_capability_context_retry ();
    (match !capability_detection_timer with
    | None -> ()
    | Some timer ->
        Clock.cancel (Eio_clock.lib_clock clock) timer;
        capability_detection_timer := None);
    ignore (O.Renderer.set_mouse_pointer renderer O.Renderer.Mouse_default);
    ignore
      (Output.write output
         (Bytes.of_string O.Lib.Ansi.modify_other_keys_reset));
    ignore
      (O.Renderer.set_cursor_position renderer ~x:1l ~y:1l ~visible:false ());
    ignore (O.Renderer.close renderer);
    ignore (Session.restore session)
  in
  (* The main fiber drives the scheduler until [exit] closes it; the background
     fibers pump input, resize signals, and dispatched events. [Eio.Fiber.first]
     cancels the losing side, so when the scheduler stops the pumps are torn
     down and [Eio.Switch.run] can return — otherwise the process lingers on the
     still-open tty until the user interrupts it again. *)
  Eio.Fiber.first
    (fun () ->
      Fun.protect
        (fun () ->
          let copy_to_clipboard text =
            let supported =
              match O.Renderer.capabilities renderer with
              | Ok (Some capabilities) ->
                  (match capabilities.O.Terminal_capabilities.osc52_support with
                  | O.Terminal_capabilities.Unsupported -> false
                  | O.Terminal_capabilities.Unknown_osc52
                  | O.Terminal_capabilities.Supported -> true)
              | Ok None | Error _ -> true
            in
            if not supported then false
            else
              match
                Output.write output
                  (O.Lib.Clipboard.osc52
                     ~selection:O.Lib.Clipboard.Clipboard text)
              with
              | Ok () -> true
              | Error _ -> false
          in
          init ~exit ~copy_to_clipboard renderer;
          (* Retained-tree mutations normally request this first frame. Keep
             the harness deterministic for demos that only configure native
             renderer state, while leaving the scheduler idle afterwards. *)
          ignore (expect_ok (O.Renderer.request_render renderer));
          match Scheduler.run scheduler with
          | Ok () -> ()
          | Error error -> invalid_arg (Scheduler.message error))
        ~finally:cleanup)
    (fun () ->
      Eio.Switch.run @@ fun bg ->
      ignore
        (Eio.Fiber.fork ~sw:bg (fun () ->
             pump_input input ~clock:mono_clock
               ~source:
                 (Eio.Resource.T (input_fd, Eio.Flow.Pi.source (module Tty_source)))
               ~queue ~wakeup));
      ignore
        (Eio.Fiber.fork ~sw:bg (fun () ->
             pump_input_timeouts input ~clock:mono_clock ~queue ~wakeup));
      ignore
        (Eio.Fiber.fork ~sw:bg (fun () ->
             let rec wait_resize () =
               match Resize.wait resize with
               | Ok () -> (
                   match Size_source.get input_fd with
                   | Ok size ->
                       ignore (Events.push queue (Events.Resize size));
                       Wakeup.notify wakeup
                   | Error _ -> ())
               | Error _ -> ();
               wait_resize ()
             in
             wait_resize ()));
      Eio.Fiber.fork ~sw:bg (fun () ->
          Dispatch.run ~queue ~wakeup
            ~handle:
              (dispatch_handle renderer ~capability_detection_active
                 ~on_pixel_resolution)))
