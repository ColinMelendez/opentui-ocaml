module Output = Eio_runtime.Output_flow

type error =
  | Unix_error of Unix.error * string * string
  | Output_error of Output.error
  | Output_and_unix_error of Output.error * Unix.error * string * string
  | Closed

type lifecycle = Ready | Entered | Restored

type t = {
  fd : Eio_unix.Fd.t;
  original : Unix.terminal_io;
  output : Output.t;
  mutable lifecycle : lifecycle;
  mutable output_restored : bool;
  mutable terminal_restored : bool;
}

let unix_message error operation argument =
  let argument =
    if String.length argument = 0 then ""
    else " (" ^ argument ^ ")"
  in
  "terminal " ^ operation ^ " failed: " ^ Unix.error_message error ^ argument

let message = function
  | Unix_error (error, operation, argument) ->
      unix_message error operation argument
  | Output_error error -> "terminal output restoration failed: " ^ Output.message error
  | Output_and_unix_error (output_error, error, operation, argument) ->
      "terminal output restoration failed: " ^ Output.message output_error
      ^ "; " ^ unix_message error operation argument
  | Closed -> "terminal session is closed"

let pp formatter error = Format.pp_print_string formatter (message error)

let raw_attributes (attributes : Unix.terminal_io) =
  {
    attributes with
    c_ignbrk = false;
    c_brkint = false;
    c_ignpar = false;
    c_parmrk = false;
    c_inpck = false;
    c_istrip = false;
    c_inlcr = false;
    c_igncr = false;
    c_icrnl = false;
    c_ixon = false;
    c_ixoff = false;
    c_opost = false;
    c_isig = false;
    c_icanon = false;
    c_noflsh = false;
    c_echo = false;
    c_echoe = false;
    c_echok = false;
    c_echonl = false;
    c_vmin = 1;
    c_vtime = 0;
  }

let enter session =
  match session.lifecycle with
  | Restored -> Error Closed
  | Entered -> Ok ()
  | Ready ->
      Eio.Cancel.protect (fun () ->
          try
            Eio_unix.Pty.Tc.setattr session.fd Unix.TCSAFLUSH
              (raw_attributes session.original);
            session.lifecycle <- Entered;
            Ok ()
          with
          | Unix.Unix_error (error, operation, argument) ->
              Error (Unix_error (error, operation, argument)))

let restore_terminal session =
  match session.lifecycle with
  | Entered ->
      (try
         Eio_unix.Pty.Tc.setattr session.fd Unix.TCSANOW session.original;
         Ok ()
       with
      | Unix.Unix_error (error, operation, argument) ->
          Error (error, operation, argument))
  | Ready | Restored -> Ok ()

let restore session =
  match session.lifecycle with
  | Restored -> Ok ()
  | Ready ->
      session.lifecycle <- Restored;
      session.output_restored <- true;
      session.terminal_restored <- true;
      Ok ()
  | Entered ->
      Eio.Cancel.protect (fun () ->
          let output_result =
            if session.output_restored then Ok ()
            else
              match Output.reset session.output with
              | Ok () as result ->
                  session.output_restored <- true;
                  result
              | Error _ as result -> result
          in
          let terminal_result =
            if session.terminal_restored then Ok ()
            else
              match restore_terminal session with
              | Ok () as result ->
                  session.terminal_restored <- true;
                  result
              | Error _ as result -> result
          in
          if session.output_restored && session.terminal_restored then
            session.lifecycle <- Restored;
          match output_result, terminal_result with
          | Ok (), Ok () -> Ok ()
          | Error output_error, Ok () -> Error (Output_error output_error)
          | Ok (), Error (error, operation, argument) ->
              Error (Unix_error (error, operation, argument))
          | Error output_error, Error (error, operation, argument) ->
              Error
                (Output_and_unix_error
                   (output_error, error, operation, argument)))

let close session =
  ignore (restore session)

let is_entered session =
  match session.lifecycle with
  | Entered -> true
  | Ready | Restored -> false

let create ~sw ~fd ~output =
  try
    let original = Eio_unix.Pty.Tc.getattr fd in
    let session =
      {
        fd;
        original;
        output;
        lifecycle = Ready;
        output_restored = false;
        terminal_restored = false;
      }
    in
    Eio.Switch.on_release sw (fun () -> close session);
    Ok session
  with
  | Unix.Unix_error (error, operation, argument) ->
      Error (Unix_error (error, operation, argument))
