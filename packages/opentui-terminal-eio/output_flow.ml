module Modes = Opentui_terminal.Terminal_modes

type error = Flow_error | Desynchronized

type t = {
  sink : Eio.Flow.sink_ty Eio.Resource.t;
  mutable state : Modes.t;
  mutable status : status;
}

and status = Healthy | Poisoned

let message = function
  | Flow_error -> "terminal Eio output flow failed"
  | Desynchronized -> "terminal Eio output flow state is desynchronized"

let pp formatter error = Format.pp_print_string formatter (message error)

let create ~sink =
  {
    sink = (sink :> Eio.Flow.sink_ty Eio.Resource.t);
    state = Modes.initial;
    status = Healthy;
  }

let screen output = Modes.screen output.state
let cursor_visible output = Modes.cursor_visible output.state
let mouse_mode output = Modes.mouse_mode output.state
let bracketed_paste output = Modes.bracketed_paste output.state

let desynchronize output error =
  output.status <- Poisoned;
  Error error

let write output bytes =
  match output.status with
  | Poisoned -> Error Desynchronized
  | Healthy ->
      if Int.equal (Bytes.length bytes) 0 then Ok ()
      else
        let rec write_remaining buffer =
          if Int.equal (Cstruct.length buffer) 0 then Ok ()
          else
            try
              let available = Cstruct.length buffer in
              let written = Eio.Flow.single_write output.sink [ buffer ] in
              if Int.compare written 0 <= 0 || Int.compare written available > 0
              then desynchronize output Flow_error
              else write_remaining (Cstruct.shift buffer written)
            with
            | Eio.Io _ -> desynchronize output Flow_error
            | Eio.Cancel.Cancelled _ as exception_value ->
                output.status <- Poisoned;
                raise exception_value
        in
        write_remaining (Cstruct.of_bytes bytes)

let apply output make_transition =
  let transition = make_transition output.state in
  match write output (Modes.output transition) with
  | Error error -> Error error
  | Ok () ->
      output.state <- Modes.next transition;
      Ok ()

let set_screen output screen =
  apply output (fun state -> Modes.set_screen state screen)

let set_cursor_visible output visible =
  apply output (fun state -> Modes.set_cursor_visible state visible)

let set_mouse output ~movement =
  apply output (fun state -> Modes.set_mouse state ~movement)

let disable_mouse output = apply output Modes.disable_mouse

let set_bracketed_paste output enabled =
  apply output (fun state -> Modes.set_bracketed_paste state enabled)

let reset output = apply output Modes.reset
