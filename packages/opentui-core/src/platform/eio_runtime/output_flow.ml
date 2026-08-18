module Modes = Lib.Terminal_modes

type error = Invalid_range | Flow_error | Desynchronized

type t = {
  sink : Eio.Flow.sink_ty Eio.Resource.t;
  mutex : Eio.Mutex.t;
  mutable state : Modes.t;
  mutable status : status;
}

and status = Healthy | Poisoned

let message = function
  | Invalid_range -> "terminal Eio output byte range is invalid"
  | Flow_error -> "terminal Eio output flow failed"
  | Desynchronized -> "terminal Eio output flow state is desynchronized"

let pp formatter error = Format.pp_print_string formatter (message error)

let create ~sink =
  {
    sink = (sink :> Eio.Flow.sink_ty Eio.Resource.t);
    mutex = Eio.Mutex.create ();
    state = Modes.initial;
    status = Healthy;
  }

let screen output = Modes.screen output.state
let cursor_visible output = Modes.cursor_visible output.state
let mouse_mode output = Modes.mouse_mode output.state
let bracketed_paste output = Modes.bracketed_paste output.state

let valid_range bytes ~off ~len =
  Int.compare off 0 >= 0
  && Int.compare len 0 >= 0
  && Int.compare off (Bytes.length bytes) <= 0
  && Int.compare len (Bytes.length bytes - off) <= 0

let write_subbytes_unlocked output ~bytes ~off ~len =
  if not (valid_range bytes ~off ~len) then Error Invalid_range
  else
    match output.status with
    | Poisoned -> Error Desynchronized
    | Healthy ->
        if Int.equal len 0 then Ok ()
        else
          let remaining = ref (Cstruct.of_bytes ~off ~len bytes) in
          let failure = ref None in
          let finished = ref false in
          while not !finished do
            if Int.equal (Cstruct.length !remaining) 0 then finished := true
            else
              match !failure with
              | Some _ -> finished := true
              | None ->
                  (try
                     let available = Cstruct.length !remaining in
                     let written =
                       Eio.Flow.single_write output.sink [ !remaining ]
                     in
                     if
                       Int.compare written 0 <= 0
                       || Int.compare written available > 0
                     then (
                       output.status <- Poisoned;
                       failure := Some Flow_error)
                     else remaining := Cstruct.shift !remaining written
                   with
                   | Eio.Io _ ->
                       output.status <- Poisoned;
                       failure := Some Flow_error
                   | Eio.Cancel.Cancelled _ as exception_value ->
                       output.status <- Poisoned;
                       raise exception_value)
          done;
          (match !failure with None -> Ok () | Some error -> Error error)

let write_subbytes output ~bytes ~off ~len =
  Eio.Mutex.use_rw output.mutex ~protect:true (fun () ->
      write_subbytes_unlocked output ~bytes ~off ~len)

let write output bytes =
  write_subbytes output ~bytes ~off:0 ~len:(Bytes.length bytes)

let write_frame output chunks =
  Eio.Mutex.use_rw output.mutex ~protect:true (fun () ->
      if
        not
          (List.for_all
             (fun bytes -> valid_range bytes ~off:0 ~len:(Bytes.length bytes))
             chunks)
      then Error Invalid_range
      else
        List.fold_left
          (fun result bytes ->
            match result with
            | Error _ -> result
            | Ok () ->
                write_subbytes_unlocked
                  output ~bytes ~off:0 ~len:(Bytes.length bytes))
          (Ok ()) chunks)

let apply output make_transition =
  Eio.Mutex.use_rw output.mutex ~protect:true (fun () ->
      let transition = make_transition output.state in
      let bytes = Modes.output transition in
      match write_subbytes_unlocked output ~bytes ~off:0 ~len:(Bytes.length bytes) with
      | Error error -> Error error
      | Ok () ->
          output.state <- Modes.next transition;
          Ok ())

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
