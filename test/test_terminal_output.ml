open Windtrap

module Modes = Opentui_terminal.Terminal_modes
module Output = Opentui_terminal_eio.Output_flow

type Eio.Exn.err += Test_output_error

module Partial_sink = struct
  type t = bool ref

  let single_write wrote buffers =
    if Int.equal (Cstruct.lenv buffers) 0 then 0
    else if not !wrote then (
      wrote := true;
      1)
    else raise (Eio.Exn.create Test_output_error)

  let copy wrote ~src = Eio.Flow.Pi.simple_copy ~single_write wrote ~src
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
  | Ok () -> ()
  | Error error -> fail (Output.message error)

let () =
  run "opentui-terminal-output"
    [
      test "poisons mode output after a partial flow error" (fun () ->
          Eio_main.run @@ fun _env ->
          let sink =
            Eio.Resource.T
              (ref false, Eio.Flow.Pi.sink (module Partial_sink))
          in
          let output = Output.create ~sink in
          (match Output.set_screen output Modes.Alternate with
          | Error Output.Flow_error -> ()
          | Error Output.Desynchronized ->
              fail "initial flow error was not reported"
          | Error Output.Invalid_range ->
              fail "mode transition produced an invalid range"
          | Ok () -> fail "a partial sink was reported as successful");
          (match Output.screen output with
          | Modes.Main -> ()
          | Modes.Alternate -> fail "failed mode transition was committed");
          (match Output.set_screen output Modes.Alternate with
          | Error Output.Desynchronized -> ()
          | Error Output.Flow_error ->
              fail "desynchronized output remained retryable"
          | Error Output.Invalid_range ->
              fail "poisoned output reported an invalid range"
          | Ok () -> fail "desynchronized output accepted a retry"));
      test "writes mode transitions and commits after the sink accepts them"
        (fun () ->
          Eio_main.run @@ fun _env ->
          let buffer = Buffer.create 32 in
          let sink = Eio.Flow.buffer_sink buffer in
          let output = Output.create ~sink in
          expect_ok (Output.set_screen output Modes.Alternate);
          equal string "\x1b[?1049h" (Buffer.contents buffer);
          (match Output.screen output with
          | Modes.Alternate -> ()
          | Modes.Main -> fail "mode state was not committed");
          expect_ok (Output.set_screen output Modes.Alternate);
          equal string "\x1b[?1049h" (Buffer.contents buffer);
          expect_ok (Output.write output (Bytes.of_string "frame"));
          equal string "\x1b[?1049hframe" (Buffer.contents buffer));
      test "writes only the requested byte subrange" (fun () ->
          Eio_main.run @@ fun _env ->
          let buffer = Buffer.create 16 in
          let sink = Eio.Flow.buffer_sink buffer in
          let output = Output.create ~sink in
          let bytes = Bytes.of_string "discardpayloadtail" in
          expect_ok
            (Output.write_subbytes output ~bytes ~off:7 ~len:7);
          equal string "payload" (Buffer.contents buffer);
          match Output.write_subbytes output ~bytes ~off:18 ~len:1 with
          | Error Output.Invalid_range -> ()
          | Error Output.Flow_error -> fail "invalid range became a flow error"
          | Error Output.Desynchronized ->
              fail "invalid range poisoned healthy output"
          | Ok () -> fail "invalid range was accepted");
      test "writes a mode transition through an Eio OS pipe" (fun () ->
          Eio_main.run @@ fun _env ->
          Eio.Switch.run @@ fun sw ->
          let source, sink = Eio_unix.pipe sw in
          let output = Output.create ~sink in
          expect_ok (Output.set_cursor_visible output false);
          let buffer = Cstruct.create 32 in
          let count = Eio.Flow.single_read source buffer in
          equal int 6 count;
          equal string "\x1b[?25l"
            (Cstruct.to_string (Cstruct.sub buffer 0 count));
          equal bool false (Output.cursor_visible output));
      test "writes a mode transition through a Unix PTY when available"
        (fun () ->
          if not (Sys.file_exists "/dev/pts") then
            skip ~reason:"the host does not expose /dev/pts" ()
          else
            try
              Eio_main.run @@ fun _env ->
              Eio.Switch.run @@ fun sw ->
              let pty = Eio_unix.Pty.open_pty ~sw () in
              let sink_handler = Eio.Flow.Pi.sink (module Tty_sink) in
              let sink =
                Eio.Resource.T (Eio_unix.Pty.tty pty, sink_handler)
              in
              let source = Eio_unix.Pty.source pty in
              let output = Output.create ~sink in
              expect_ok (Output.set_cursor_visible output false);
              let buffer = Cstruct.create 32 in
              let count = Eio.Flow.single_read source buffer in
              equal int 6 count;
              equal string "\x1b[?25l"
                (Cstruct.to_string (Cstruct.sub buffer 0 count));
              equal bool false (Output.cursor_visible output)
            with
            | Unix.Unix_error
                ((Unix.ENOTTY | Unix.EOPNOTSUPP | Unix.ENOENT), _, _) ->
                skip ~reason:"the host PTY implementation is unavailable" ())
    ]
