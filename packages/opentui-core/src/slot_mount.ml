type mode = Append | Replace | Single_winner

type fallback = unit -> (Slot_view.t list, Plugin_failure.t) result
type placeholder = Plugin_failure.t -> (Slot_view.t list, Plugin_failure.t) result

type owned_view = {
  owned_view : Slot_view.t;
  owned_plugin : Plugin_id.t option;
}

type plugin_state = {
  state_key : int;
  mutable state_view : owned_view option;
  mutable state_props_generation : int;
}

type 'props t = {
  mount_slot : 'props Slot.t;
  mount_renderable : Renderable.t;
  mount_children : Layout_children.t;
  mount_fallback : fallback option;
  mount_placeholder : placeholder option;
  mutable mount_props : 'props;
  mutable mount_props_generation : int;
  mutable mount_mode : mode;
  mutable mount_states : plugin_state list;
  mutable mount_fallback_views : owned_view list option;
  mutable mount_current_views : owned_view list;
  mutable mount_subscription : Slot.Private.subscription option;
  mutable mount_refreshing : bool;
  mutable mount_destroyed : bool;
  mutable mount_cleaned : bool;
}

let slot_id mount = Slot.Private.id mount.mount_slot
let slot_host mount = Slot.Private.host mount.mount_slot
let host_is_open mount = Plugin_host.Private.is_open (slot_host mount)

let make_failure mount ?plugin ~phase ~origin cause =
  Plugin_failure.make ?plugin ~slot:(slot_id mount) ~phase ~origin ~cause ()

let context_failure mount ?plugin failure ~phase ~origin =
  match plugin with
  | None ->
      Plugin_failure.with_context failure ~slot:(slot_id mount) ~phase ~origin ()
  | Some plugin_id ->
      Plugin_failure.with_context failure ~plugin:plugin_id
        ~slot:(slot_id mount) ~phase ~origin ()

let plugin_context_failure mount plugin_id failure ~phase =
  context_failure mount ~plugin:plugin_id failure ~phase
    ~origin:Plugin_failure.Plugin

let host_context_failure mount failure ~phase =
  context_failure mount failure ~phase ~origin:Plugin_failure.Host

let renderer_failure mount ~phase error =
  make_failure mount ~phase ~origin:Plugin_failure.Retained_tree
    (Plugin_failure.Renderer_error error)

let invalid_view_failure mount ?plugin error =
  make_failure mount ?plugin ~phase:Plugin_failure.Render ~origin:Plugin_failure.Host
    (Plugin_failure.Invalid_view error)

let append_failures left right = left @ right

let failure_result failures =
  match failures with
  | [] -> Ok ()
  | first :: rest -> Error (first :: rest)

let mode_equal left right =
  match left, right with
  | Append, Append | Replace, Replace | Single_winner, Single_winner -> true
  | Append, Replace | Append, Single_winner | Replace, Append
  | Replace, Single_winner | Single_winner, Append
  | Single_winner, Replace -> false

let is_empty = function [] -> true | _ :: _ -> false

let rec contains_renderable renderable = function
  | [] -> false
  | current :: rest ->
      if (Slot_view.renderable current.owned_view) == renderable
      then true
      else contains_renderable renderable rest

let contains_owned_renderable owned views =
  contains_renderable (Slot_view.renderable owned.owned_view) views

let add_unique_owned owned views =
  if contains_owned_renderable owned views then views else views @ [ owned ]

let all_old_views mount =
  let from_states =
    List.fold_left
      (fun views state ->
        match state.state_view with
        | None -> views
        | Some owned -> add_unique_owned owned views)
      [] mount.mount_states
  in
  let with_fallback =
    match mount.mount_fallback_views with
    | None -> from_states
    | Some views ->
        List.fold_left
          (fun acc view -> add_unique_owned view acc)
          from_states views
  in
  List.fold_left
    (fun views current -> add_unique_owned current views)
    with_fallback mount.mount_current_views

let dispose_unaccepted_view view =
  let renderable = Slot_view.renderable view in
  if not (Renderable.is_destroyed renderable) then
    Renderable.destroy_recursively renderable;
  Slot_view.Private.destroy view

let dispose_unaccepted_views views =
  List.iter (fun owned -> dispose_unaccepted_view owned.owned_view) views

let detach_owned_view mount owned =
  let renderable = Slot_view.renderable owned.owned_view in
  match Renderable.parent renderable with
  | Some parent when parent == mount.mount_renderable ->
      (match Layout_children.remove mount.mount_children renderable with
      | Ok () -> []
      | Error error -> [ renderer_failure mount ~phase:Plugin_failure.Destroy error ])
  | Some _ | None -> []

let deactivate_owned_view mount owned =
  if not (Slot_view.Private.is_active owned.owned_view) then []
  else
    match Slot_view.Private.deactivate owned.owned_view with
    | Ok () -> []
    | Error failure ->
        let phase = Plugin_failure.Deactivate in
        [
          (match owned.owned_plugin with
          | None -> host_context_failure mount failure ~phase
          | Some plugin_id -> plugin_context_failure mount plugin_id failure ~phase);
        ]

let cleanup_owned_view mount owned =
  let failures = deactivate_owned_view mount owned in
  let detach_failures = detach_owned_view mount owned in
  let renderable = Slot_view.renderable owned.owned_view in
  if not (Renderable.is_destroyed renderable) then
    Renderable.destroy_recursively renderable;
  Slot_view.Private.destroy owned.owned_view;
  append_failures failures detach_failures

let cleanup_owned_views mount views =
  List.fold_left
    (fun failures owned ->
      append_failures failures (cleanup_owned_view mount owned))
    [] views

let validate_view mount ?plugin view =
  let renderable = Slot_view.renderable view in
  if Slot_view.Private.is_destroyed view || Renderable.is_destroyed renderable then
    Error (invalid_view_failure mount ?plugin Plugin_failure.View_destroyed)
  else if renderable == mount.mount_renderable then
    Error (invalid_view_failure mount ?plugin Plugin_failure.View_is_mount)
  else if
    not
      (Render_context.same_owner (Renderable.context renderable)
         (Renderable.context mount.mount_renderable))
  then Error (invalid_view_failure mount ?plugin Plugin_failure.View_wrong_renderer)
  else
    match Renderable.parent renderable with
    | None -> Ok ()
    | Some _ ->
        Error (invalid_view_failure mount ?plugin Plugin_failure.View_attached)

let validate_distinct_views mount views =
  let rec loop seen = function
    | [] -> Ok ()
    | owned :: rest ->
        let renderable = Slot_view.renderable owned.owned_view in
        if contains_renderable renderable seen then
          Error
            (invalid_view_failure mount ?plugin:owned.owned_plugin
               Plugin_failure.View_duplicate)
        else loop (seen @ [ owned ]) rest
  in
  loop [] views

let prepare_views mount ?plugin ~phase views =
  let validate_all () =
    List.fold_left
      (fun result view ->
        match result with
        | Error _ -> result
        | Ok () -> validate_view mount ?plugin view)
      (Ok ()) views
  in
  match validate_all () with
  | Error failure ->
      dispose_unaccepted_views
        (List.map
           (fun view -> { owned_view = view; owned_plugin = plugin })
           views);
      Error [ failure ]
  | Ok () ->
      let owned =
        List.map
          (fun view -> { owned_view = view; owned_plugin = plugin })
          views
      in
      let claim_failure = ref None in
      List.iter
        (fun current ->
          match !claim_failure with
          | Some _ -> ()
          | None ->
              (match Slot_view.Private.claim current.owned_view with
              | Ok () -> ()
              | Error failure -> claim_failure := Some failure))
        owned;
      (match !claim_failure with
      | Some failure ->
          dispose_unaccepted_views owned;
          let contextual =
            match plugin with
            | None -> host_context_failure mount failure ~phase
            | Some plugin_id -> plugin_context_failure mount plugin_id failure ~phase
          in
          Error [ contextual ]
      | None ->
          let activation_failure = ref None in
          List.iter
            (fun current ->
              match !activation_failure with
              | Some _ -> ()
              | None ->
                  (match Slot_view.Private.activate current.owned_view with
                  | Ok () -> ()
                  | Error failure -> activation_failure := Some failure))
            owned;
          (match !activation_failure with
          | None -> Ok owned
          | Some failure ->
              let cleanup_failures = cleanup_owned_views mount owned in
              let contextual =
                match plugin with
                | None ->
                    host_context_failure mount failure
                      ~phase:Plugin_failure.Activate
                | Some plugin_id ->
                    plugin_context_failure mount plugin_id failure
                      ~phase:Plugin_failure.Activate
              in
              Error (contextual :: cleanup_failures)))

let fallback_views_valid mount views =
  List.for_all
    (fun owned ->
      let view = owned.owned_view in
      let renderable = Slot_view.renderable view in
      not (Slot_view.Private.is_destroyed view)
      && not (Renderable.is_destroyed renderable)
      &&
      match Renderable.parent renderable with
      | None -> true
      | Some parent -> parent == mount.mount_renderable)
    views

let call_fallback mount =
  match mount.mount_fallback with
  | None -> [], []
  | Some callback ->
      let result =
        try callback () with
        | exception_value ->
            Error
              (Plugin_failure.callback_exception ~slot:(slot_id mount)
                 ~phase:Plugin_failure.Fallback ~origin:Plugin_failure.Host
                 exception_value ())
      in
      (match result with
      | Error failure ->
          [],
          [ host_context_failure mount failure ~phase:Plugin_failure.Fallback ]
      | Ok views ->
          (match prepare_views mount ~phase:Plugin_failure.Fallback views with
          | Ok owned -> owned, []
          | Error failures -> [], failures))

let call_placeholder mount ~plugin failure =
  match mount.mount_placeholder with
  | None -> [], []
  | Some callback ->
      let result =
        try callback failure with
        | exception_value ->
            Error
              (Plugin_failure.callback_exception ~plugin ~slot:(slot_id mount)
                 ~phase:Plugin_failure.Placeholder ~origin:Plugin_failure.Host
                 exception_value ())
      in
      (match result with
      | Error placeholder_failure ->
          [],
          [
            Plugin_failure.with_context placeholder_failure ~plugin
              ~slot:(slot_id mount) ~phase:Plugin_failure.Placeholder
              ~origin:Plugin_failure.Host ();
          ]
      | Ok views ->
          (match
             prepare_views mount ~plugin ~phase:Plugin_failure.Placeholder views
           with
          | Ok owned -> owned, []
          | Error failures -> [], failures))

let render_plugin mount contribution state =
  let instance = Slot.Private.contribution_instance contribution in
  let plugin_id = Plugin_host.Instance.id instance in
  let render_result =
    try Slot.Private.contribution_render contribution mount.mount_props with
    | exception_value ->
        Error
          (Plugin_failure.callback_exception ~plugin:plugin_id ~slot:(slot_id mount)
             ~phase:Plugin_failure.Render ~origin:Plugin_failure.Plugin
             exception_value ())
  in
  match render_result with
  | Ok None -> state, [], [], None
  | Ok (Some view) ->
      (match
         prepare_views mount ~plugin:plugin_id ~phase:Plugin_failure.Render [ view ]
       with
      | Ok [ owned ] ->
          state.state_view <- Some owned;
          state.state_props_generation <- mount.mount_props_generation;
          state, [], [ owned ], Some owned
      | Ok _ ->
          state.state_view <- None;
          state.state_props_generation <- mount.mount_props_generation;
          state, [], [], None
      | Error failures ->
          state.state_view <- None;
          state.state_props_generation <- mount.mount_props_generation;
          let render_failures =
            List.map
              (fun failure ->
                plugin_context_failure mount plugin_id failure
                  ~phase:Plugin_failure.Render)
              failures
          in
          let trigger =
            match render_failures with
            | first :: _ -> first
            | [] ->
                make_failure mount ~plugin:plugin_id ~phase:Plugin_failure.Render
                  ~origin:Plugin_failure.Plugin Plugin_failure.Busy
          in
          let placeholder_views, placeholder_failures =
            call_placeholder mount ~plugin:plugin_id trigger
          in
          state, render_failures @ placeholder_failures, placeholder_views, None)
  | Error failure ->
      state.state_view <- None;
      state.state_props_generation <- mount.mount_props_generation;
      let contextual =
        plugin_context_failure mount plugin_id failure ~phase:Plugin_failure.Render
      in
      let placeholder_views, placeholder_failures =
        call_placeholder mount ~plugin:plugin_id contextual
      in
      state, contextual :: placeholder_failures, placeholder_views, None

let active_contributions mount contributions =
  match mount.mount_mode, contributions with
  | Single_winner, first :: _ -> [ first ]
  | Single_winner, [] -> []
  | Append, _ | Replace, _ -> contributions

let find_state key states =
  List.find_opt (fun state -> Int.equal state.state_key key) states

let state_is_reusable mount state =
  match state.state_view with
  | None -> false
  | Some owned ->
      state.state_props_generation = mount.mount_props_generation
      && not (Slot_view.Private.is_destroyed owned.owned_view)
      && not (Renderable.is_destroyed (Slot_view.renderable owned.owned_view))

let new_views_not_in_old old_views views =
  List.filter
    (fun owned -> not (contains_owned_renderable owned old_views))
    views

let reconcile mount desired =
  let desired_renderables =
    List.map (fun owned -> Slot_view.renderable owned.owned_view) desired
  in
  let current = Renderable.children mount.mount_renderable in
  let failures = ref [] in
  List.iter
    (fun child ->
      if not
           (List.exists
              (fun desired_child -> desired_child == child)
              desired_renderables)
      then
        match Layout_children.remove mount.mount_children child with
        | Ok () -> ()
        | Error error ->
            failures :=
              !failures
              @ [ renderer_failure mount ~phase:Plugin_failure.Refresh error ])
    current;
  List.iteri
    (fun index child ->
      let current_children = Renderable.children mount.mount_renderable in
      let at_index =
        let rec find current_index = function
          | [] -> None
          | value :: rest ->
              if Int.equal current_index index then Some value
              else find (current_index + 1) rest
        in
        find 0 current_children
      in
      match at_index with
      | Some current when current == child -> ()
      | Some _ | None ->
          (match Layout_children.add ~index mount.mount_children child with
          | Ok _ -> ()
          | Error error ->
              failures :=
                !failures
                @ [ renderer_failure mount ~phase:Plugin_failure.Refresh error ]))
    desired_renderables;
  match !failures with
  | [] -> Ok ()
  | first :: rest -> Error (first :: rest)

let report_failures mount failures =
  List.iter (Plugin_host.Private.report (slot_host mount)) failures

let refresh_internal mount =
  if mount.mount_destroyed || Renderable.is_destroyed mount.mount_renderable then
    [
      make_failure mount ~phase:Plugin_failure.Refresh ~origin:Plugin_failure.Host
        Plugin_failure.Host_closed;
    ]
  else if not (host_is_open mount) then begin
    Option.iter Slot.Private.unsubscribe mount.mount_subscription;
    mount.mount_subscription <- None;
    let failures = cleanup_owned_views mount (all_old_views mount) in
    mount.mount_states <- [];
    mount.mount_fallback_views <- None;
    mount.mount_current_views <- [];
    failures
  end
  else if mount.mount_refreshing then
    [
      make_failure mount ~phase:Plugin_failure.Refresh ~origin:Plugin_failure.Host
        Plugin_failure.Busy;
    ]
  else begin
    mount.mount_refreshing <- true;
    let old_views = all_old_views mount in
    let contributions = Slot.Private.contributions mount.mount_slot in
    let active = active_contributions mount contributions in
    let active_keys =
      List.map
        (fun contribution ->
          Plugin_host.Private.instance_sequence
            (Slot.Private.contribution_instance contribution))
        active
    in
    let inactive_states, retained_states =
      List.partition
        (fun state -> not (List.exists (Int.equal state.state_key) active_keys))
        mount.mount_states
    in
    let failures = ref [] in
    let next_states = ref [] in
    let plugin_outputs = ref [] in
    List.iter
      (fun contribution ->
        let instance = Slot.Private.contribution_instance contribution in
        let key = Plugin_host.Private.instance_sequence instance in
        let previous = find_state key retained_states in
        let state =
          match previous with
          | Some state -> state
          | None ->
              {
                state_key = key;
                state_view = None;
                state_props_generation = -1;
              }
        in
        let state, state_failures, outputs =
          if state_is_reusable mount state then
            state, [], Option.to_list state.state_view
          else begin
            state.state_view <- None;
            let state, state_failures, outputs, _ =
              render_plugin mount contribution state
            in
            state, state_failures, outputs
          end
        in
        failures := !failures @ state_failures;
        plugin_outputs := !plugin_outputs @ outputs;
        next_states := !next_states @ [ state ])
      active;
    let plugin_views = !plugin_outputs in
    let fallback_needed =
      match mount.mount_mode with
      | Append -> true
      | Replace | Single_winner -> List.is_empty plugin_views
    in
    let fallback_views, fallback_failures =
      if not fallback_needed then [], []
      else
        match mount.mount_fallback_views with
        | Some views when fallback_views_valid mount views -> views, []
        | Some _ | None -> call_fallback mount
    in
    failures := !failures @ fallback_failures;
    let desired =
      match mount.mount_mode with
      | Append -> fallback_views @ plugin_views
      | Replace | Single_winner ->
          if List.is_empty plugin_views then fallback_views else plugin_views
    in
    (match validate_distinct_views mount desired with
    | Error failure ->
        failures := !failures @ [ failure ];
        let fresh = new_views_not_in_old old_views desired in
        failures := !failures @ cleanup_owned_views mount fresh
    | Ok () ->
        (match reconcile mount desired with
        | Error reconcile_failures ->
            failures := !failures @ reconcile_failures;
            let fresh = new_views_not_in_old old_views desired in
            dispose_unaccepted_views fresh
        | Ok () ->
            let obsolete =
              List.filter
                (fun owned -> not (contains_owned_renderable owned desired))
                old_views
            in
            failures := !failures @ cleanup_owned_views mount obsolete;
            mount.mount_states <- !next_states;
            mount.mount_fallback_views <-
              if fallback_needed && not (List.is_empty fallback_views) then
                Some fallback_views
              else None;
            mount.mount_current_views <- desired;
            ignore (Renderable.request_render mount.mount_renderable)));
    mount.mount_refreshing <- false;
    !failures
  end

let cleanup_mount mount =
  if not mount.mount_cleaned then begin
    mount.mount_cleaned <- true;
    Option.iter Slot.Private.unsubscribe mount.mount_subscription;
    mount.mount_subscription <- None;
    let failures = cleanup_owned_views mount (all_old_views mount) in
    mount.mount_states <- [];
    mount.mount_fallback_views <- None;
    mount.mount_current_views <- [];
    report_failures mount failures
  end

let destroy mount =
  if not mount.mount_destroyed then begin
    mount.mount_destroyed <- true;
    Renderable.destroy mount.mount_renderable
  end

let create ~renderer ~slot ~props ?(mode = Append) ?fallback ?placeholder () =
  let slot_renderer = Plugin_host.Private.renderer (Slot.Private.host slot) in
  if
    not
      (Render_context.same_owner (Renderer.context renderer)
         (Renderer.context slot_renderer))
  then
    Error
      (Plugin_failure.make ~slot:(Slot.Private.id slot) ~phase:Plugin_failure.Create
         ~origin:Plugin_failure.Host
         ~cause:(Plugin_failure.Renderer_error Error.Owner_mismatch) ())
  else
    let mount_ref = ref None in
    let behavior =
      Renderable.Private.make_behavior
        ~destroy_self:(fun _ ->
          match !mount_ref with
          | None -> ()
          | Some mount ->
              mount.mount_destroyed <- true;
              cleanup_mount mount)
        ()
    in
    match Renderable.Private.create (Renderer.context renderer) ~behavior () with
    | Error error ->
        Error
          (Plugin_failure.make ~slot:(Slot.Private.id slot)
             ~phase:Plugin_failure.Create ~origin:Plugin_failure.Retained_tree
             ~cause:(Plugin_failure.Renderer_error error) ())
    | Ok mount_renderable ->
        let mount =
          {
            mount_slot = slot;
            mount_renderable;
            mount_children = Layout_children.Private.of_renderable mount_renderable;
            mount_fallback = fallback;
            mount_placeholder = placeholder;
            mount_props = props;
            mount_props_generation = 0;
            mount_mode = mode;
            mount_states = [];
            mount_fallback_views = None;
            mount_current_views = [];
            mount_subscription = None;
            mount_refreshing = false;
            mount_destroyed = false;
            mount_cleaned = false;
          }
        in
        mount_ref := Some mount;
        (match
           Slot.Private.subscribe slot ~notify:(fun () -> refresh_internal mount)
         with
        | Error failure ->
            Renderable.destroy mount_renderable;
            Error (host_context_failure mount failure ~phase:Plugin_failure.Create)
        | Ok subscription ->
            mount.mount_subscription <- Some subscription;
            report_failures mount (refresh_internal mount);
            Ok mount)

let renderable mount = mount.mount_renderable
let mode mount = mount.mount_mode

let set_props mount props =
  if mount.mount_destroyed || Renderable.is_destroyed mount.mount_renderable
     || not (host_is_open mount)
  then
    Error
      [
        make_failure mount ~phase:Plugin_failure.Refresh
          ~origin:Plugin_failure.Host Plugin_failure.Host_closed;
      ]
  else if mount.mount_refreshing then
    Error
      [
        make_failure mount ~phase:Plugin_failure.Refresh
          ~origin:Plugin_failure.Host Plugin_failure.Busy;
      ]
  else begin
    mount.mount_props <- props;
    mount.mount_props_generation <- mount.mount_props_generation + 1;
    failure_result (refresh_internal mount)
  end

let set_mode mount value =
  if mount.mount_destroyed || Renderable.is_destroyed mount.mount_renderable
     || not (host_is_open mount)
  then
    Error
      [
        make_failure mount ~phase:Plugin_failure.Refresh
          ~origin:Plugin_failure.Host Plugin_failure.Host_closed;
      ]
  else if mount.mount_refreshing then
    Error
      [
        make_failure mount ~phase:Plugin_failure.Refresh
          ~origin:Plugin_failure.Host Plugin_failure.Busy;
      ]
  else if mode_equal mount.mount_mode value then Ok ()
  else begin
    mount.mount_mode <- value;
    failure_result (refresh_internal mount)
  end

let refresh mount =
  if not (host_is_open mount) then
    Error
      [
        make_failure mount ~phase:Plugin_failure.Refresh
          ~origin:Plugin_failure.Host Plugin_failure.Host_closed;
      ]
  else failure_result (refresh_internal mount)

let is_destroyed mount =
  mount.mount_destroyed || Renderable.is_destroyed mount.mount_renderable
