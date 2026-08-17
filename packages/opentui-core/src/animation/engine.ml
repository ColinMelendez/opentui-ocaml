type registration = {
  engine : t;
  token_id : int;
  root : Timeline.t;
  roots : Timeline.t list ref;
  listeners : (Timeline.t * int) list ref;
  auto_release : bool;
  mutable active : bool;
}

and run_once = {
  registration : registration;
  mutable cancelled : bool;
}

and t = {
  engine_id : int;
  mutable next_token_id : int;
  mutable registrations : registration list;
  mutable destroyed : bool;
  mutable renderer : Renderer.t option;
  mutable pre_render : Renderer.pre_render_driver option;
  mutable before_destroy : Renderer.teardown_attachment option;
  mutable live_lease : Renderer.live_lease option;
  on_failure : failure -> unit;
  mutable diagnostics : diagnostic list;
}

and failure = {
  timeline_id : int;
  fault : Timeline.fault;
}

and diagnostic =
  | Timeline_failure of failure
  | Engine_failure of Error.t
  | Renderer_failure of string
  | Failure_callback_exception of exn

let next_engine_id = ref 0

let fresh_engine_id () =
  let value = !next_engine_id in
  next_engine_id := value + 1;
  value

let create ?(on_failure = fun _ -> ()) () =
  {
    engine_id = fresh_engine_id ();
    next_token_id = 0;
    registrations = [];
    destroyed = false;
    renderer = None;
    pre_render = None;
    before_destroy = None;
    live_lease = None;
    on_failure;
    diagnostics = [];
  }

let add_diagnostic engine diagnostic =
  engine.diagnostics <- diagnostic :: engine.diagnostics

let report_failure engine failure =
  add_diagnostic engine (Timeline_failure failure);
  try engine.on_failure failure with
  | exception_value ->
      add_diagnostic engine (Failure_callback_exception exception_value)

let report_renderer_failure engine error =
  add_diagnostic engine (Renderer_failure (Opentui_core__Error.message error))

let report_engine_failure engine error =
  add_diagnostic engine (Engine_failure error)

let animation_error_of_renderer error =
  Error.user ~detail:(Opentui_core__Error.message error) "renderer"

let rec subtree timeline =
  timeline :: List.concat (List.map subtree (Timeline.Private.subtree timeline))

let has_running_registration registration =
  List.exists
    (fun timeline ->
      Timeline.Private.is_playing timeline
      && not (Timeline.is_complete timeline))
    !(registration.roots)

let has_running_engine engine =
  List.exists has_running_registration engine.registrations

let refresh_live engine =
  match engine.renderer, has_running_engine engine, engine.live_lease with
  | Some renderer, true, None ->
      (match Renderer.acquire_live_lease renderer with
      | Ok lease -> engine.live_lease <- Some lease
      | Error error -> report_renderer_failure engine error)
  | Some _, false, Some lease ->
      Renderer.release_live_lease lease;
      engine.live_lease <- None
  | Some _, _, _ | None, _, _ -> ()

let promote_registration registration child =
  if registration.active then begin
    if not (List.exists (fun current -> current == child) !(registration.roots))
    then registration.roots := !(registration.roots) @ [ child ];
    refresh_live registration.engine
  end

let remove_registration engine registration =
  engine.registrations <-
    List.filter (fun current -> current != registration) engine.registrations

let release_registration registration =
  if registration.active then begin
    registration.active <- false;
    let engine = registration.engine in
    List.iter
      (fun (timeline, listener_id) ->
        Timeline.Private.remove_state_listener timeline listener_id)
      !(registration.listeners);
    registration.listeners := [];
    List.iter
      (fun timeline ->
        Timeline.Private.detach_engine timeline ~engine_id:engine.engine_id
          ~token_id:registration.token_id)
      !(registration.roots);
    registration.roots := [];
    remove_registration engine registration;
    refresh_live engine
  end

let release registration = release_registration registration

let ensure_open engine =
  if engine.destroyed then Error Error.Engine_destroyed else Ok ()

let register_internal engine ~auto_release timeline =
  match ensure_open engine with
  | Error error -> Error error
  | Ok () ->
      let token_id = engine.next_token_id in
      engine.next_token_id <- token_id + 1;
      let roots = ref [ timeline ] in
      let listeners = ref [] in
      let registration_ref : registration option ref = ref None in
      let promote child =
        match !registration_ref with
        | None -> ()
        | Some registration -> promote_registration registration child
      in
      (match
         Timeline.Private.attach_engine timeline ~engine_id:engine.engine_id
           ~token_id ~promote
       with
      | Error error -> Error error
      | Ok () ->
          let registration =
            {
              engine;
              token_id;
              root = timeline;
              roots;
              listeners;
              auto_release;
              active = true;
            }
          in
          registration_ref := Some registration;
          let nodes = subtree timeline in
          List.iter
            (fun node ->
              let listener_id =
                Timeline.Private.add_state_listener node (fun changed ->
                    if registration.active && registration.auto_release
                       && changed == registration.root
                       && (Timeline.is_complete changed
                          || Option.is_some (Timeline.fault changed))
                    then release_registration registration;
                    refresh_live engine)
              in
              listeners := (node, listener_id) :: !listeners)
            nodes;
          engine.registrations <- engine.registrations @ [ registration ];
          refresh_live engine;
          Ok registration)

let register engine timeline = register_internal engine ~auto_release:false timeline

let run_once engine timeline =
  match register_internal engine ~auto_release:true timeline with
  | Error error -> Error error
  | Ok registration ->
      (match Timeline.play timeline with
      | Ok () -> Ok { registration; cancelled = false }
      | Error error ->
          release_registration registration;
          Error error)

let cancel run_once =
  if run_once.cancelled then Ok ()
  else begin
    run_once.cancelled <- true;
    let registration = run_once.registration in
    let pause_result =
      if registration.active && Timeline.Private.is_playing
           (List.hd !(registration.roots))
      then Timeline.pause (List.hd !(registration.roots))
      else Ok ()
    in
    release_registration registration;
    pause_result
  end

let update engine ~delta_time_ms =
  match ensure_open engine with
  | Error error -> Error error
  | Ok () when not (Float.is_finite delta_time_ms) ->
      Error (Error.Invalid_number { field = "update delta"; value = delta_time_ms })
  | Ok () when Float.compare delta_time_ms 0.0 < 0 ->
      Error (Error.Negative_number { field = "update delta"; value = delta_time_ms })
  | Ok () ->
      let failures = ref [] in
      let registrations = engine.registrations in
      List.iter
        (fun registration ->
          if registration.active then
            let roots = !(registration.roots) in
            List.iter
              (fun timeline ->
                if registration.active
                   && Timeline.Private.is_engine_root timeline
                        ~engine_id:engine.engine_id
                then
                  match
                    Timeline.Private.engine_update timeline
                      ~engine_id:engine.engine_id ~delta_time_ms
                  with
                  | Ok () -> ()
                  | Error fault ->
                      failures :=
                        { timeline_id = Timeline.id timeline; fault }
                        :: !failures)
              roots)
        registrations;
      refresh_live engine;
      let failures = List.rev !failures in
      List.iter (report_failure engine) failures;
      Ok failures

let detach engine =
  Option.iter Renderer.detach_pre_render engine.pre_render;
  engine.pre_render <- None;
  Option.iter Renderer.detach_before_destroy engine.before_destroy;
  engine.before_destroy <- None;
  Option.iter Renderer.release_live_lease engine.live_lease;
  engine.live_lease <- None;
  engine.renderer <- None

let destroy engine =
  if not engine.destroyed then begin
    engine.destroyed <- true;
    detach engine;
    let registrations = engine.registrations in
    List.iter release_registration registrations;
    engine.registrations <- []
  end

let attach engine ~renderer =
  match ensure_open engine with
  | Error error -> Error error
  | Ok () when Option.is_some engine.renderer ->
      Error (Error.Invalid_operation Error.Register)
  | Ok () ->
      let callback delta_seconds =
        match update engine ~delta_time_ms:(delta_seconds *. 1000.0) with
        | Ok _ -> ()
        | Error error -> report_engine_failure engine error
      in
      (match Renderer.attach_pre_render renderer callback with
      | Error error -> Error (animation_error_of_renderer error)
      | Ok pre_render ->
          let teardown () = destroy engine in
          (match Renderer.attach_before_destroy renderer teardown with
          | Error error ->
              Renderer.detach_pre_render pre_render;
              Error (animation_error_of_renderer error)
          | Ok before_destroy ->
              engine.renderer <- Some renderer;
              engine.pre_render <- Some pre_render;
              engine.before_destroy <- Some before_destroy;
              refresh_live engine;
              Ok ()))

let clear engine =
  match ensure_open engine with
  | Error error -> Error error
  | Ok () ->
      let registrations = engine.registrations in
      List.iter release_registration registrations;
      Ok ()

let diagnostics engine = List.rev engine.diagnostics
