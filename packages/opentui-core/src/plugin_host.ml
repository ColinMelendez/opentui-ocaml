type errors = Plugin_failure.t * Plugin_failure.t list

type host_state = Open | Closing | Closed
type scope_state = Scope_open | Scope_sealed | Scope_released
type instance_state = Installing | Installed | Uninstalling | Uninstalled

type staged_contribution = {
  slot_id : Plugin_id.t;
  slot_key : int;
  publish : instance -> (unit, Plugin_failure.t) result;
  withdraw : instance -> (unit, Plugin_failure.t) result;
  notify : unit -> Plugin_failure.t list;
}

and release_action = unit -> (unit, Plugin_failure.t) result

and 'capabilities definition = {
  definition_id : Plugin_id.t;
  definition_order : int;
  definition_install : scope -> 'capabilities -> (unit, Plugin_failure.t) result;
}

and scope = {
  scope_host : t;
  mutable scope_state : scope_state;
  mutable staged : staged_contribution list;
  mutable releases : release_action list;
}

and instance = {
  instance_host : t;
  instance_id : Plugin_id.t;
  mutable instance_order : int;
  instance_sequence : int;
  mutable instance_state : instance_state;
  mutable instance_contributions : staged_contribution list;
  mutable instance_releases : release_action list;
  mutable terminal_uninstall : (unit, errors) result option;
}

and t = {
  host_renderer : Renderer.t;
  host_reporter : Plugin_reporter.t;
  mutable host_teardown : Renderer.teardown_attachment option;
  mutable host_state : host_state;
  mutable next_sequence : int;
  mutable next_slot_key : int;
  mutable slot_ids : (Plugin_id.t * int) list;
  mutable instances : instance list;
  mutable host_busy : int;
  mutable terminal_close : (unit, errors) result option;
}

let make_failure ?plugin ?slot ~phase ~origin cause =
  Plugin_failure.make ?plugin ?slot ~phase ~origin ~cause ()

let error_pair failures =
  match failures with
  | [] -> Ok ()
  | first :: rest -> Error (first, rest)

let add_context failure ?plugin ?slot ~phase ~origin () =
  Plugin_failure.with_context failure ?plugin ?slot ~phase ~origin ()

let host_failure host cause =
  let phase = Plugin_failure.Install in
  let origin = Plugin_failure.Host in
  make_failure ~phase ~origin cause

let ensure_host_open host ~phase =
  match host.host_state with
  | Open -> Ok ()
  | Closing | Closed ->
      Error
        (make_failure ~phase ~origin:Plugin_failure.Host
           Plugin_failure.Host_closed)

let ensure_host_not_busy host ~phase =
  if Int.equal host.host_busy 0 then Ok ()
  else
    Error
      (make_failure ~phase ~origin:Plugin_failure.Host Plugin_failure.Busy)

let rec mem_slot_key key contributions =
  match contributions with
  | [] -> false
  | current :: rest ->
      if Int.equal current.slot_key key then true
      else mem_slot_key key rest

let rec unique_slot_keys seen contributions =
  match contributions with
  | [] -> []
  | current :: rest ->
      if List.exists (Int.equal current.slot_key) seen then
        unique_slot_keys seen rest
      else current :: unique_slot_keys (current.slot_key :: seen) rest

let report_failures host failures =
  List.iter (Plugin_reporter.report host.host_reporter) failures

let compare_instances left right =
  let order = Int.compare left.instance_order right.instance_order in
  if not (Int.equal order 0) then order
  else Int.compare left.instance_sequence right.instance_sequence

let run_release ~plugin ~phase action =
  try
    match action () with
    | Ok () -> None
    | Error failure ->
        Some
          (add_context failure ~plugin ~phase ~origin:Plugin_failure.Plugin ())
  with
  | exception_value ->
      Some
        (Plugin_failure.callback_exception ~plugin ~phase
           ~origin:Plugin_failure.Plugin exception_value ())

let rollback_scope scope ~plugin failures =
  scope.scope_state <- Scope_released;
  let cleanup_failures =
    List.filter_map
      (run_release ~plugin ~phase:Plugin_failure.Rollback)
      (List.rev scope.releases)
  in
  failures @ cleanup_failures

let stage_contribution scope ~slot_id ~slot_key ~publish ~withdraw ~notify =
  match scope.scope_state with
  | Scope_sealed | Scope_released ->
      Error
        (make_failure ~slot:slot_id ~phase:Plugin_failure.Install
           ~origin:Plugin_failure.Plugin Plugin_failure.Scope_closed)
  | Scope_open ->
      (match ensure_host_open scope.scope_host ~phase:Plugin_failure.Install with
      | Error failure -> Error failure
      | Ok () ->
          if mem_slot_key slot_key scope.staged then
            Error
              (make_failure ~slot:slot_id ~phase:Plugin_failure.Install
                 ~origin:Plugin_failure.Plugin
                 (Plugin_failure.Duplicate_slot slot_id))
          else begin
            scope.staged <-
              scope.staged @ [ { slot_id; slot_key; publish; withdraw; notify } ];
            Ok ()
          end)

let on_release scope action =
  match scope.scope_state with
  | Scope_sealed | Scope_released ->
      Error
        (make_failure ~phase:Plugin_failure.Install
           ~origin:Plugin_failure.Plugin Plugin_failure.Scope_closed)
  | Scope_open ->
      scope.releases <- scope.releases @ [ action ];
      Ok ()

let define ~id ~order ~install =
  Ok
    {
      definition_id = id;
      definition_order = order;
      definition_install = install;
    }

let create ~renderer ~reporter =
  {
    host_renderer = renderer;
    host_reporter = reporter;
    host_teardown = None;
    host_state = Open;
    next_sequence = 0;
    next_slot_key = 0;
    slot_ids = [];
    instances = [];
    host_busy = 0;
    terminal_close = None;
  }

let register_slot host id =
  match ensure_host_open host ~phase:Plugin_failure.Create with
  | Error failure -> Error failure
  | Ok () ->
      (match ensure_host_not_busy host ~phase:Plugin_failure.Create with
      | Error failure -> Error failure
      | Ok () ->
          if List.exists (fun (current, _) -> Plugin_id.equal current id) host.slot_ids
          then
            Error
              (make_failure ~slot:id ~phase:Plugin_failure.Create
                 ~origin:Plugin_failure.Host (Plugin_failure.Duplicate_slot id))
          else
            let key = host.next_slot_key in
            host.next_slot_key <- key + 1;
            host.slot_ids <- host.slot_ids @ [ id, key ];
            Ok key)

let notify_contributions host contributions =
  let unique = unique_slot_keys [] contributions in
  List.fold_left
    (fun failures contribution ->
      failures @ contribution.notify ())
    [] unique

let publish_staged instance staged =
  let published = ref [] in
  let failure = ref None in
  List.iter
    (fun contribution ->
      match !failure with
      | Some _ -> ()
      | None ->
          (match contribution.publish instance with
          | Ok () -> published := contribution :: !published
          | Error current -> failure := Some current))
    staged;
  match !failure with
  | None -> Ok ()
  | Some current ->
      List.iter
        (fun contribution -> ignore (contribution.withdraw instance))
        !published;
      Error current

let remove_instance host instance =
  host.instances <-
    List.filter
      (fun current ->
        not (Int.equal current.instance_sequence instance.instance_sequence))
      host.instances

let release_instance instance ~phase =
  let failures =
    List.filter_map
      (run_release ~plugin:instance.instance_id ~phase)
      (List.rev instance.instance_releases)
  in
  failures

let uninstall_instance host instance =
  match instance.instance_state with
  | Uninstalled ->
      Option.value instance.terminal_uninstall ~default:(Ok ())
  | Installing ->
      Error
        (make_failure ~plugin:instance.instance_id ~phase:Plugin_failure.Uninstall
           ~origin:Plugin_failure.Host Plugin_failure.Busy,
         [])
  | Uninstalling ->
      Error
        (make_failure ~plugin:instance.instance_id ~phase:Plugin_failure.Uninstall
           ~origin:Plugin_failure.Host Plugin_failure.Busy,
         [])
  | Installed ->
      instance.instance_state <- Uninstalling;
      let withdrawal_failures =
        List.filter_map
          (fun contribution ->
            match contribution.withdraw instance with
            | Ok () -> None
            | Error failure ->
                Some
                  (add_context failure ~plugin:instance.instance_id
                     ~phase:Plugin_failure.Uninstall
                     ~origin:Plugin_failure.Host ()))
          instance.instance_contributions
      in
      let refresh_failures =
        notify_contributions host instance.instance_contributions
        |> List.map (fun failure ->
               add_context failure ~plugin:instance.instance_id
                 ~phase:Plugin_failure.Uninstall ~origin:Plugin_failure.Host ())
      in
      let cleanup_failures =
        release_instance instance ~phase:Plugin_failure.Uninstall
      in
      remove_instance host instance;
      instance.instance_state <- Uninstalled;
      let result =
        error_pair (withdrawal_failures @ refresh_failures @ cleanup_failures)
      in
      instance.terminal_uninstall <- Some result;
      result

let install host ~capabilities definition =
  match ensure_host_open host ~phase:Plugin_failure.Install with
  | Error failure -> Error (failure, [])
  | Ok () ->
      (match ensure_host_not_busy host ~phase:Plugin_failure.Install with
      | Error failure -> Error (failure, [])
      | Ok () ->
          if List.exists
               (fun current ->
                 Plugin_id.equal current.instance_id definition.definition_id)
               host.instances
          then
            Error
              ( make_failure ~plugin:definition.definition_id
                  ~phase:Plugin_failure.Install ~origin:Plugin_failure.Host
                  (Plugin_failure.Duplicate_plugin definition.definition_id),
                [] )
          else begin
            let sequence = host.next_sequence in
            host.next_sequence <- sequence + 1;
            let instance =
              {
                instance_host = host;
                instance_id = definition.definition_id;
                instance_order = definition.definition_order;
                instance_sequence = sequence;
                instance_state = Installing;
                instance_contributions = [];
                instance_releases = [];
                terminal_uninstall = None;
              }
            in
            let scope =
              {
                scope_host = host;
                scope_state = Scope_open;
                staged = [];
                releases = [];
              }
            in
            host.host_busy <- host.host_busy + 1;
            let setup_result =
              try definition.definition_install scope capabilities with
              | exception_value ->
                  Error
                    (Plugin_failure.callback_exception
                       ~plugin:definition.definition_id
                       ~phase:Plugin_failure.Install ~origin:Plugin_failure.Plugin
                       exception_value ())
            in
            host.host_busy <- host.host_busy - 1;
            match setup_result with
            | Error failure ->
                let failures =
                  rollback_scope scope ~plugin:definition.definition_id
                    [
                      add_context failure ~plugin:definition.definition_id
                        ~phase:Plugin_failure.Install
                        ~origin:Plugin_failure.Plugin ();
                    ]
                in
                Error
                  (match failures with
                  | first :: rest -> first, rest
                  | [] ->
                      make_failure ~plugin:definition.definition_id
                        ~phase:Plugin_failure.Rollback
                        ~origin:Plugin_failure.Host Plugin_failure.Scope_closed,
                      [])
            | Ok () ->
                scope.scope_state <- Scope_sealed;
                instance.instance_releases <- scope.releases;
                host.host_busy <- host.host_busy + 1;
                let publish_result = publish_staged instance scope.staged in
                (match publish_result with
                | Error failure ->
                    host.host_busy <- host.host_busy - 1;
                    let failures =
                      rollback_scope scope ~plugin:definition.definition_id
                        [
                          add_context failure ~plugin:definition.definition_id
                            ~phase:Plugin_failure.Install
                            ~origin:Plugin_failure.Host ();
                        ]
                    in
                    Error
                      (match failures with
                      | first :: rest -> first, rest
                      | [] ->
                          make_failure ~plugin:definition.definition_id
                            ~phase:Plugin_failure.Rollback
                            ~origin:Plugin_failure.Host Plugin_failure.Scope_closed,
                          [])
                | Ok () ->
                    instance.instance_contributions <- scope.staged;
                    instance.instance_state <- Installed;
                    host.instances <- host.instances @ [ instance ];
                    let notification_failures =
                      notify_contributions host instance.instance_contributions
                    in
                    host.host_busy <- host.host_busy - 1;
                    report_failures host notification_failures;
                    Ok instance)
          end)

let renderer host = host.host_renderer
let is_open host = match host.host_state with Open -> true | Closing | Closed -> false
let report host failure = Plugin_reporter.report host.host_reporter failure

let instance_id instance = instance.instance_id
let instance_order instance = instance.instance_order

let set_order instance order =
  let host = instance.instance_host in
  match instance.instance_state with
  | Uninstalled ->
      Error
        (make_failure ~plugin:instance.instance_id ~phase:Plugin_failure.Set_order
           ~origin:Plugin_failure.Host Plugin_failure.Already_uninstalled)
  | Installing | Uninstalling ->
      Error
        (make_failure ~plugin:instance.instance_id ~phase:Plugin_failure.Set_order
           ~origin:Plugin_failure.Host Plugin_failure.Busy)
  | Installed ->
      (match ensure_host_open host ~phase:Plugin_failure.Set_order with
      | Error failure -> Error failure
      | Ok () ->
          (match ensure_host_not_busy host ~phase:Plugin_failure.Set_order with
          | Error failure -> Error failure
          | Ok () ->
              if Int.equal instance.instance_order order then Ok ()
              else begin
                instance.instance_order <- order;
                host.host_busy <- host.host_busy + 1;
                let failures = notify_contributions host instance.instance_contributions in
                host.host_busy <- host.host_busy - 1;
                report_failures host
                  (List.map
                     (fun failure ->
                       add_context failure ~plugin:instance.instance_id
                         ~phase:Plugin_failure.Set_order
                         ~origin:Plugin_failure.Host ())
                     failures);
                Ok ()
              end))

let close host =
  match host.terminal_close with
  | Some result -> result
  | None ->
      (match host.host_state with
      | Closed -> Ok ()
      | Closing ->
          Error
            (make_failure ~phase:Plugin_failure.Uninstall
               ~origin:Plugin_failure.Host Plugin_failure.Busy,
             [])
      | Open ->
          (match ensure_host_not_busy host ~phase:Plugin_failure.Uninstall with
          | Error failure -> Error (failure, [])
          | Ok () ->
              host.host_state <- Closing;
              (match host.host_teardown with
              | None -> ()
              | Some attachment ->
                  host.host_teardown <- None;
                  Renderer.detach_before_destroy attachment);
              host.host_busy <- host.host_busy + 1;
              let failures =
                List.fold_left
                  (fun failures instance ->
                    match uninstall_instance host instance with
                    | Ok () -> failures
                    | Error (first, rest) -> failures @ (first :: rest))
                  [] (List.rev host.instances)
              in
              host.host_busy <- host.host_busy - 1;
              host.host_state <- Closed;
              let result = error_pair failures in
              host.terminal_close <- Some result;
              result))

module Scope = struct
  type t = scope
  let on_release = on_release
end

module Instance = struct
  type t = instance
  let id = instance_id
  let order = instance_order
  let set_order = set_order
  let uninstall instance =
    let host = instance.instance_host in
    match instance.instance_state with
    | Uninstalled -> Option.value instance.terminal_uninstall ~default:(Ok ())
    | Installing | Uninstalling ->
        Error
          (make_failure ~plugin:instance.instance_id
             ~phase:Plugin_failure.Uninstall ~origin:Plugin_failure.Host
             Plugin_failure.Busy,
           [])
    | Installed ->
        (match ensure_host_open host ~phase:Plugin_failure.Uninstall with
        | Error failure -> Error (failure, [])
        | Ok () ->
            (match ensure_host_not_busy host ~phase:Plugin_failure.Uninstall with
            | Error failure -> Error (failure, [])
            | Ok () ->
                host.host_busy <- host.host_busy + 1;
                let result = uninstall_instance host instance in
                host.host_busy <- host.host_busy - 1;
                result))
end

module Host = struct
  type nonrec t = t
  let create ~renderer ~reporter =
    let host = create ~renderer ~reporter in
    match
      Renderer.attach_before_destroy renderer (fun () ->
          match close host with
          | Ok () -> ()
          | Error (first, rest) -> report_failures host (first :: rest))
    with
    | Ok attachment ->
        host.host_teardown <- Some attachment;
        host
    | Error _ ->
        host.host_state <- Closed;
        host.terminal_close <- Some (Ok ());
        host
  let install = install
  let close = close
end

module Private = struct
  let register_slot = register_slot
  let stage_contribution = stage_contribution
  let scope_host scope = scope.scope_host
  let renderer = renderer
  let is_open = is_open
  let report = report
  let instance_sequence instance = instance.instance_sequence
  let compare_instances = compare_instances
end
