type signal = {
  condition : Eio.Condition.t;
  mutable revision : int64;
}

let create_signal () = { condition = Eio.Condition.create (); revision = 0L }

let signal_revision signal = signal.revision

let notify signal =
  signal.revision <-
    if Int64.equal signal.revision Int64.max_int then 0L
    else Int64.add signal.revision 1L;
  Eio.Condition.broadcast signal.condition

let wait_for_signal signal ~since ~closed =
  Eio.Condition.loop_no_mutex signal.condition (fun () ->
      if closed () || not (Int64.equal signal.revision since) then Some ()
      else None)

type error =
  | Closed
  | Missing_clock
  | Wrong_domain
  | Switch_mismatch
  | Clock_mismatch
  | Already_attached
  | Already_running
  | Invalid_frames_per_second
  | Render_error of Error.t

let message = function
  | Closed -> "the renderer scheduler is closed"
  | Missing_clock -> "the renderer has no owner-local clock capability"
  | Wrong_domain -> "the renderer scheduler must run in its owner Eio domain"
  | Switch_mismatch ->
      "the renderer scheduler switch is not the Eio clock's owner switch"
  | Clock_mismatch ->
      "the renderer clock is not the Eio clock supplied to the scheduler"
  | Already_attached -> "the renderer already has a scheduler"
  | Already_running -> "the renderer scheduler is already running"
  | Invalid_frames_per_second ->
      "renderer scheduler frames_per_second must be positive"
  | Render_error error ->
      "renderer scheduler frame failed: " ^ Error.message error

let pp formatter error = Format.pp_print_string formatter (message error)

type renderer_state = {
  pending : bool;
  live : int;
}

type t = {
  clock : Eio_clock.t;
  renderer : Renderer.t;
  interval : float;
  signal : signal;
  mutable wakeup : Render_context.Private.scheduler_wakeup option;
  mutable destroy_subscription : Event_subscription.t option;
  mutable release_target : t option ref option;
  mutable closed : bool;
  mutable running : bool;
  mutable last_attempt : float option;
  mutable next_deadline : float option;
}

let renderer_state scheduler =
  match Renderer.has_pending_render scheduler.renderer with
  | Error Error.Closed -> Error Closed
  | Error error -> Error (Render_error error)
  | Ok pending ->
      (match Renderer.live_request_count scheduler.renderer with
      | Error Error.Closed -> Error Closed
      | Error error -> Error (Render_error error)
      | Ok live -> Ok { pending; live })

let reset_timing scheduler =
  scheduler.last_attempt <- None;
  scheduler.next_deadline <- None

let advance_deadline scheduler deadline ~now =
  if Float.compare deadline now > 0 then deadline
  else
    let elapsed = now -. deadline in
    let skipped = Float.floor (elapsed /. scheduler.interval) +. 1.0 in
    let candidate = deadline +. (skipped *. scheduler.interval) in
    if Float.compare candidate now > 0 then candidate
    else Float.next_after now Float.infinity

let update_deadline scheduler ~attempt_time ~after_time ~live =
  if Int.compare live 0 > 0 then begin
    let first_target =
      match scheduler.next_deadline with
      | None -> attempt_time +. scheduler.interval
      | Some previous -> previous +. scheduler.interval
    in
    scheduler.next_deadline <-
      Some (advance_deadline scheduler first_target ~now:after_time)
  end
  else scheduler.next_deadline <- None

let render_one scheduler =
  let attempt_time = Eio_clock.now scheduler.clock in
  let delta_time =
    match scheduler.last_attempt with
    | None -> 0.0
    | Some previous -> max 0.0 (attempt_time -. previous)
  in
  scheduler.last_attempt <- Some attempt_time;
  match Renderer.render scheduler.renderer ~delta_time ~force:false with
  | Error (Error.Output _ as error) ->
      (* An output failure means the terminal transport may be
         desynchronized. It is terminal for this scheduler; retrying would
         only create a hot loop against a poisoned sink. *)
      Error (Render_error error)
  | Error error ->
      (* [Renderer.render] restores the coalesced request and emits the
         renderer-owned error event. Keep retrying, but pace the next attempt
         so a persistent failure cannot become a hot loop. *)
      scheduler.next_deadline <-
        Some (Eio_clock.now scheduler.clock +. scheduler.interval);
      ignore error;
      Ok ()
  | Ok status ->
      ignore status;
      (match renderer_state scheduler with
      | Error error -> Error error
      | Ok state ->
          let live = state.live in
          update_deadline scheduler ~attempt_time
            ~after_time:(Eio_clock.now scheduler.clock) ~live;
          Ok ())

let wait_idle scheduler =
  Eio.Condition.loop_no_mutex scheduler.signal.condition (fun () ->
      if scheduler.closed then Some ()
      else
        match renderer_state scheduler with
        | Error error ->
            ignore error;
            Some ()
        | Ok state ->
            if state.pending || Int.compare state.live 0 > 0 then Some ()
            else None)

let wait_until_deadline scheduler ~deadline ~wake_on_signal =
  let waiting = ref true in
  while !waiting && not scheduler.closed do
    if Float.compare (Eio_clock.now scheduler.clock) deadline >= 0 then
      waiting := false
    else begin
      let since = signal_revision scheduler.signal in
      let outcome =
        Eio.Fiber.first
          (fun () ->
            Eio_clock.sleep_until scheduler.clock ~deadline;
            `Deadline)
          (fun () ->
            wait_for_signal scheduler.signal ~since
              ~closed:(fun () -> scheduler.closed);
            `Signal)
      in
      match outcome with
      | `Deadline -> waiting := false
      | `Signal when not wake_on_signal -> ()
      | `Signal ->
          (match renderer_state scheduler with
          | Error Closed -> waiting := false
          | Error error ->
              ignore error;
              waiting := false
          | Ok state ->
              let live = state.live in
              if Int.compare live 0 <= 0 then waiting := false)
    end
  done

let run_loop scheduler =
  let result = ref (Ok ()) in
  let continue_running = ref true in
  while !continue_running do
    if scheduler.closed then continue_running := false
    else
      match renderer_state scheduler with
      | Error error ->
          result := Error error;
          continue_running := false
      | Ok state ->
          if not state.pending && Int.compare state.live 0 <= 0 then begin
            reset_timing scheduler;
            wait_idle scheduler
          end
          else
            match scheduler.next_deadline with
            | Some deadline
              when Float.compare (Eio_clock.now scheduler.clock) deadline < 0 ->
                wait_until_deadline scheduler ~deadline
                  ~wake_on_signal:(Int.compare state.live 0 > 0)
            | Some _ | None ->
                (match render_one scheduler with
                | Ok () -> ()
                | Error error ->
                    result := Error error;
                    continue_running := false)
  done;
  !result

let close_unchecked scheduler =
  if not scheduler.closed then begin
    scheduler.closed <- true;
    notify scheduler.signal;
    (match scheduler.wakeup with
    | None -> ()
    | Some wakeup ->
        Render_context.Private.remove_scheduler_wakeup
          (Renderer.context scheduler.renderer) wakeup;
        scheduler.wakeup <- None);
    (match scheduler.destroy_subscription with
    | None -> ()
    | Some subscription ->
        Event_subscription.cancel subscription;
        scheduler.destroy_subscription <- None);
    (* The clock belongs to its explicit Eio switch, not to this scheduler
       attachment. Clearing the release indirection also prevents a long-lived
       switch callback from retaining the scheduler and renderer tree. *)
    Option.iter (fun target -> target := None) scheduler.release_target;
    scheduler.release_target <- None
  end

let close scheduler =
  if not (Eio_clock.owns_domain scheduler.clock) then Error Wrong_domain
  else begin
    close_unchecked scheduler;
    Ok ()
  end

let create ~sw ~clock ~renderer ?(frames_per_second = 60) () =
  if Int.compare frames_per_second 0 <= 0 then Error Invalid_frames_per_second
  else if Renderer.is_destroyed renderer then Error Closed
  else
    match Eio_clock.check clock ~sw with
    | Error Eio_clock.Closed -> Error Closed
    | Error Eio_clock.Wrong_domain -> Error Wrong_domain
    | Error Eio_clock.Switch_mismatch -> Error Switch_mismatch
    | Ok () ->
        (match Render_context.clock (Renderer.context renderer) with
        | Error Error.Closed -> Error Closed
        | Error error -> Error (Render_error error)
        | Ok None -> Error Missing_clock
        | Ok (Some renderer_clock)
          when not (Eio_clock.owns_lib_clock clock renderer_clock) ->
            Error Clock_mismatch
        | Ok (Some renderer_clock) ->
            ignore renderer_clock;
        let scheduler =
          {
            clock;
            renderer;
            interval = 1.0 /. float_of_int frames_per_second;
            signal = create_signal ();
            wakeup = None;
            destroy_subscription = None;
            release_target = None;
            closed = false;
            running = false;
            last_attempt = None;
            next_deadline = None;
          }
        in
        (match
           Render_context.Private.install_scheduler_wakeup
             (Renderer.context renderer)
             (fun () -> notify scheduler.signal)
         with
        | None ->
            if Renderer.is_destroyed renderer then Error Closed
            else Error Already_attached
        | Some wakeup ->
            scheduler.wakeup <- Some wakeup;
            (match
               Renderer.once_destroy renderer (fun () -> close_unchecked scheduler)
             with
            | Error Error.Closed ->
                Render_context.Private.remove_scheduler_wakeup
                  (Renderer.context renderer) wakeup;
                Error Closed
            | Error error ->
                Render_context.Private.remove_scheduler_wakeup
                  (Renderer.context renderer) wakeup;
                Error (Render_error error)
            | Ok subscription ->
                scheduler.destroy_subscription <- Some subscription;
                let release_target = ref (Some scheduler) in
                Eio.Switch.on_release sw (fun () ->
                    Option.iter close_unchecked !release_target);
                scheduler.release_target <- Some release_target;
                Ok scheduler)))

let run scheduler =
  if not (Eio_clock.owns_domain scheduler.clock) then Error Wrong_domain
  else if scheduler.closed then Ok ()
  else
    match Eio_clock.check_owner scheduler.clock with
    | Error Eio_clock.Closed -> Error Closed
    | Error Eio_clock.Wrong_domain -> Error Wrong_domain
    | Error Eio_clock.Switch_mismatch -> Error Switch_mismatch
    | Ok () ->
        if scheduler.running then Error Already_running
        else begin
          scheduler.running <- true;
          Fun.protect
            (fun () -> run_loop scheduler)
            ~finally:(fun () ->
              scheduler.running <- false;
              close_unchecked scheduler)
        end
