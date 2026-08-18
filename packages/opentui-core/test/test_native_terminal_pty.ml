open Windtrap

module Native = Opentui_core.Renderer
module Native_buffer = Opentui_core.Buffer
module Output = Opentui_core.Platform.Eio_runtime.Output_flow
module Input_flow = Opentui_core.Platform.Eio_runtime.Input_flow
module Size_source = Opentui_core.Platform.Eio_unix_runtime.Terminal_size_source
module Session = Opentui_core.Platform.Eio_unix_runtime.Terminal_session
module Input = Opentui_core.Lib.Stdin_parser
module Events = Opentui_core.Lib.Event_queue
module Modes = Opentui_core.Lib.Terminal_modes
module Size = Opentui_core.Lib.Terminal_size

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

let expect_native_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Opentui_core.Error.message error)

let expect_output_ok result =
  match result with
  | Ok () -> ()
  | Error error -> fail (Output.message error)

let expect_input_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Input_flow.message error)

let expect_size_source result =
  match result with
  | Ok value -> value
  | Error error -> fail (Size_source.message error)

let expect_session result =
  match result with
  | Ok session -> session
  | Error error -> fail (Session.message error)

let expect_session_ok result =
  match result with
  | Ok () -> ()
  | Error error -> fail (Session.message error)

let read_exact source length =
  let result = Bytes.create length in
  let rec read_remaining offset =
    if Int.equal offset length then ()
    else
      let destination = Cstruct.create (length - offset) in
      let count = Eio.Flow.single_read source destination in
      Cstruct.blit_to_bytes destination 0 result offset count;
      read_remaining (offset + count)
  in
  read_remaining 0;
  Bytes.to_string result

let terminal_size pty =
  expect_size_source (Size_source.get (Eio_unix.Pty.tty pty))

let set_window_size pty ~columns ~rows =
  Eio_unix.Pty.set_window_size (Eio_unix.Pty.pty pty)
    { Eio_unix.Pty.rows = rows; cols = columns; xpixel = 0; ypixel = 0 }

let render_text renderer output ~text ~width =
  let buffer = expect_native_ok (Native.next_buffer renderer) in
  ignore
    (expect_native_ok
       (Native_buffer.clear buffer ~background:Opentui_core.Color.black));
  ignore
    (expect_native_ok
       (Native_buffer.draw_text buffer ~text ~x:0l ~y:0l
          ~foreground:Opentui_core.Color.white
          ~background:Opentui_core.Color.black ~attributes:0l));
  let bytes = Bytes.create width in
  let written =
    expect_native_ok
      (Native_buffer.write_resolved_chars buffer ~output:bytes
         ~add_line_breaks:false)
  in
  equal int32 (Int32.of_int width) written;
  expect_output_ok
    (Output.write_subbytes output ~bytes ~off:0
       ~len:(Int32.to_int written));
  match Native.render renderer ~force:true
  with
  | Ok Native.Rendered -> ()
  | Ok Native.Skipped -> fail "PTY frame was unexpectedly skipped"
  | Ok Native.Failed -> fail "PTY frame failed"
  | Error error -> fail (Opentui_core.Error.message error)

let () =
  run "opentui-core-pty"
    [
      test "composes modes input resize native frames and restoration" (fun () ->
          if not (Sys.file_exists "/dev/pts") then
            skip ~reason:"the host does not expose /dev/pts" ()
          else
            try
              Eio_main.run @@ fun env ->
              Eio.Switch.run @@ fun sw ->
              let pty = Eio_unix.Pty.open_pty ~sw () in
              let tty = Eio_unix.Pty.tty pty in
              let original_attributes = Eio_unix.Pty.Tc.getattr tty in
              set_window_size pty ~columns:2 ~rows:1;
              let size = terminal_size pty in
              equal int 2 (Size.columns size);
              equal int 1 (Size.rows size);
              let input_source =
                Eio.Resource.T
                  (tty, Eio.Flow.Pi.source (module Tty_source))
              in
              let output_sink =
                Eio.Resource.T
                  (tty, Eio.Flow.Pi.sink (module Tty_sink))
              in
              let input = expect_input_ok (Input_flow.create ~buffer_size:32 ()) in
              let queue =
                match Events.create ~capacity:4 () with
                | Ok value -> value
                | Error error -> fail (Events.message error)
              in
              let emit event =
                match Events.push queue (Events.Input event) with
                | Ok () -> Opentui_core.Lib.Input_coordinator.Accepted
                | Error Events.Full ->
                    Opentui_core.Lib.Input_coordinator.Full
                | Error Events.Invalid_capacity ->
                    fail "a queue created successfully reported Invalid_capacity"
              in
              let output = Output.create ~sink:output_sink in
              let session =
                expect_session (Session.create ~sw ~fd:tty ~output)
              in
              expect_session_ok (Session.enter session);
              let raw_attributes = Eio_unix.Pty.Tc.getattr tty in
              equal bool false raw_attributes.c_icanon;
              equal bool false raw_attributes.c_echo;
              equal bool false raw_attributes.c_isig;
              equal bool false raw_attributes.c_opost;
              equal bool false raw_attributes.c_ixon;
              equal bool false raw_attributes.c_ixoff;
              equal int 1 raw_attributes.c_vmin;
              equal int 0 raw_attributes.c_vtime;
              let renderer =
                expect_native_ok
                  (Native.create ~output:Native.Output.Memory ~width:2l
                     ~height:1l ())
              in
              expect_output_ok (Output.set_screen output Modes.Alternate);
              equal string "\x1b[?1049h"
                (read_exact (Eio_unix.Pty.source pty) 8);
              expect_output_ok (Output.set_cursor_visible output false);
              equal string "\x1b[?25l"
                (read_exact (Eio_unix.Pty.source pty) 6);
              render_text renderer output ~text:"AB" ~width:2;
              equal string "AB" (read_exact (Eio_unix.Pty.source pty) 2);
              Eio.Flow.copy_string "\x1b[A" (Eio_unix.Pty.sink pty);
              let clock = Eio.Stdenv.mono_clock env in
              (match
               Input_flow.read_once input ~clock ~source:input_source ~emit
               with
              | Ok (Input_flow.Bytes_read 3) -> ()
              | Ok Input_flow.End_of_input ->
                  fail "PTY input ended before the arrow key"
              | Ok (Input_flow.Backpressured _) ->
                  fail "PTY input was unexpectedly backpressured"
              | Ok (Input_flow.Bytes_read count) ->
                  fail (Printf.sprintf "expected three input bytes, got %d" count)
              | Error error -> fail (Input_flow.message error));
              set_window_size pty ~columns:3 ~rows:1;
              let resized = terminal_size pty in
              match Events.push queue (Events.Resize resized) with
              | Error error -> fail (Events.message error)
              | Ok () ->
                  (match Events.read queue with
                  | Some
                      (Events.Input
                        (Input.Key
                          {
                            key = Opentui_core.Lib.Key_decoder.Named Up;
                            _;
                          })) ->
                      ()
                  | Some _ -> fail "PTY input decoded as the wrong event"
                  | None -> fail "PTY input event was lost");
                  (match Events.read queue with
                  | Some (Events.Resize size) ->
                      equal int 3 (Size.columns size);
                      equal int 1 (Size.rows size)
                  | Some _ -> fail "PTY resize was delivered as input"
                  | None -> fail "PTY resize event was lost");
                  ignore
                    (expect_native_ok
                       (Native.resize renderer ~width:3l ~height:1l));
                  render_text renderer output ~text:"CDE" ~width:3;
                  equal string "CDE" (read_exact (Eio_unix.Pty.source pty) 3);
                  expect_session_ok (Session.restore session);
                  let reset_output = "\x1b[?25h\x1b[0m\x1b[?1049l" in
                  equal string reset_output
                    (read_exact (Eio_unix.Pty.source pty)
                       (String.length reset_output));
                  (match Output.screen output with
                  | Modes.Main -> ()
                  | Modes.Alternate -> fail "PTY output did not restore screen");
                  equal bool true (Output.cursor_visible output);
                  let restored_attributes = Eio_unix.Pty.Tc.getattr tty in
                  equal bool original_attributes.c_icanon
                    restored_attributes.c_icanon;
                  equal bool original_attributes.c_echo
                    restored_attributes.c_echo;
                  equal bool original_attributes.c_isig
                    restored_attributes.c_isig;
                  equal bool original_attributes.c_opost
                    restored_attributes.c_opost;
                  equal bool original_attributes.c_ixon
                    restored_attributes.c_ixon;
                  equal bool original_attributes.c_ixoff
                    restored_attributes.c_ixoff;
                  equal int original_attributes.c_vmin restored_attributes.c_vmin;
                  equal int original_attributes.c_vtime restored_attributes.c_vtime;
                  Native.destroy renderer
            with
            | Unix.Unix_error
                ((Unix.ENOTTY | Unix.EOPNOTSUPP | Unix.ENOENT), _, _) ->
                skip ~reason:"the host PTY implementation is unavailable" ())
    ]
