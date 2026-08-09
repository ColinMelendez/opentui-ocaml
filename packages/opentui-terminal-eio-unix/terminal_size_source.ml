module Size = Opentui_terminal.Terminal_size

type error =
  | Unix_error of Unix.error * string * string
  | Invalid_dimensions

let message = function
  | Unix_error (error, operation, argument) ->
      let argument =
        if String.length argument = 0 then ""
        else " (" ^ argument ^ ")"
      in
      "terminal size query " ^ operation ^ " failed: "
      ^ Unix.error_message error ^ argument
  | Invalid_dimensions -> Size.message Size.Invalid_dimensions

let pp formatter error = Format.pp_print_string formatter (message error)

let get fd =
  try
    let window = Eio_unix.Pty.get_window_size fd in
    match Size.create ~columns:window.cols ~rows:window.rows with
    | Ok size -> Ok size
    | Error Size.Invalid_dimensions -> Error Invalid_dimensions
  with
  | Unix.Unix_error (error, operation, argument) ->
      Error (Unix_error (error, operation, argument))
