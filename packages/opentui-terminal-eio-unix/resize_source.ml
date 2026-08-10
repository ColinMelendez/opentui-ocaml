type error =
  | Already_installed
  | Existing_handler
  | Closed

type t = {
  condition : Eio.Condition.t;
  mutable pending : bool;
  mutable closed : bool;
  previous : Sys.signal_behavior;
}

let active : t option ref = ref None

(* The signal handler and the condition's no-mutex wait are owned by the one
   Eio domain that owns the terminal runtime. The process-global handler is
   deliberately not a multi-domain registry. *)

let message = function
  | Already_installed -> "a terminal resize signal source is already installed"
  | Existing_handler ->
      "SIGWINCH already has a non-default process handler"
  | Closed -> "terminal resize signal source is closed"

let pp formatter error = Format.pp_print_string formatter (message error)

let close source =
  if not source.closed then (
    source.closed <- true;
    Sys.set_signal Sys.sigwinch source.previous;
    (match !active with
    | Some current when current == source -> active := None
    | Some _ | None -> ());
    Eio.Condition.broadcast source.condition)

let create ~sw () =
  match !active with
  | Some _ -> Error Already_installed
  | None ->
      let previous = Sys.signal Sys.sigwinch Sys.Signal_ignore in
      (match previous with
      | Sys.Signal_handle _ ->
          Sys.set_signal Sys.sigwinch previous;
          Error Existing_handler
      | Sys.Signal_default | Sys.Signal_ignore ->
          let source =
            {
              condition = Eio.Condition.create ();
              pending = false;
              closed = false;
              previous;
            }
          in
          Sys.set_signal Sys.sigwinch
            (Sys.Signal_handle (fun _ ->
                 source.pending <- true;
                 Eio.Condition.broadcast source.condition));
          active := Some source;
          Eio.Switch.on_release sw (fun () -> close source);
          Ok source)

let wait source =
  if source.closed then Error Closed
  else
    let outcome =
      Eio.Condition.loop_no_mutex source.condition (fun () ->
          if source.closed then Some false
          else if source.pending then (
            source.pending <- false;
            Some true)
          else None)
    in
    if outcome then Ok () else Error Closed
