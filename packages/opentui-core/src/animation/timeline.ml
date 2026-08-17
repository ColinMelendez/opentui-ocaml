type state = Idle | Playing | Paused | Completed | Faulted

type loops = Once | Count of int | Infinite

type update = {
  progress : float;
  current_time_ms : float;
  delta_time_ms : float;
}

type fault = Error.fault

type numeric_item = {
  id : int;
  start_time_ms : float;
  duration_ms : float;
  easing : Easing.t;
  loops : loops;
  loop_delay_ms : float;
  alternate : bool;
  once : bool;
  bindings : Property.binding list;
  mutable initial_values : float list option;
  mutable started : bool;
  mutable completed : bool;
  mutable last_cycle : int;
  on_update : (update -> unit) option;
  on_start : (unit -> unit) option;
  on_loop : (unit -> unit) option;
  on_complete : (unit -> unit) option;
}

type callback_item = {
  id : int;
  start_time_ms : float;
  callback : unit -> unit;
  mutable called : bool;
}

type item = Numeric of numeric_item | Callback of callback_item

type sync_token = {
  parent : t;
  child : t;
  offset_ms : float;
  token_id : int;
  mutable started : bool;
  mutable active : bool;
}

and t = {
  timeline_id : int;
  duration_ms : float;
  loop : bool;
  mutable state : state;
  mutable current_time_ms : float;
  mutable items : item list;
  mutable next_item_id : int;
  mutable next_sync_id : int;
  mutable sync_parent : sync_token option;
  mutable sync_children : sync_token list;
  mutable engine_owner : int option;
  mutable engine_token_id : int option;
  mutable engine_promote : (t -> unit) option;
  mutable updating : bool;
  mutable fault : Error.fault option;
  on_complete : (unit -> unit) option;
  on_pause : (unit -> unit) option;
  mutable next_listener_id : int;
  mutable state_listeners : (int * (t -> unit)) list;
}

let next_timeline_id = ref 0

let fresh_timeline_id () =
  let value = !next_timeline_id in
  next_timeline_id := value + 1;
  value

let finite field value =
  if Float.is_finite value then Ok ()
  else Error (Error.Invalid_number { field; value })

let nonnegative field value =
  match finite field value with
  | Error error -> Error error
  | Ok () when Float.compare value 0.0 < 0 ->
      Error (Error.Negative_number { field; value })
  | Ok () -> Ok ()

let make_fault ?item_id ?binding_index timeline phase cause =
  {
    Error.item_id = item_id;
    binding_index;
    timeline_time_ms = timeline.current_time_ms;
    phase;
    cause;
  }

let notify_state timeline =
  let snapshot = timeline.state_listeners in
  List.iter (fun (_, callback) -> callback timeline) snapshot

let set_state timeline state =
  timeline.state <- state;
  notify_state timeline

let fail timeline ?item_id ?binding_index phase cause =
  let value = make_fault ?item_id ?binding_index timeline phase cause in
  timeline.fault <- Some value;
  set_state timeline Faulted;
  Error value

let callback_failure timeline ?item_id phase exception_value =
  fail timeline ?item_id phase
    (Error.Exception (Error.exception_info exception_value))

let validate_loops = function
  | Once | Infinite -> Ok ()
  | Count count when Int.compare count 0 > 0 -> Ok ()
  | Count count -> Error (Error.Invalid_loop_count count)

let validate_bindings bindings =
  let first_error = ref None in
  List.iter
    (fun binding ->
      match !first_error, Property.Private.validate binding with
      | Some _, _ -> ()
      | None, Ok () -> ()
      | None, Error error -> first_error := Some error)
    bindings;
  match !first_error with None -> Ok () | Some error -> Error error

let create ?(duration_ms = 1000.0) ?(loop = false) ?(autoplay = true)
    ?on_complete ?on_pause () =
  match nonnegative "duration" duration_ms with
  | Error error -> Error error
  | Ok () when loop && Float.equal duration_ms 0.0 ->
      Error Error.Loop_requires_positive_duration
  | Ok () ->
      let timeline_id = fresh_timeline_id () in
      Ok
        {
          timeline_id;
          duration_ms;
          loop;
          state = if autoplay then Playing else Idle;
          current_time_ms = 0.0;
          items = [];
          next_item_id = 0;
          next_sync_id = 0;
          sync_parent = None;
          sync_children = [];
          engine_owner = None;
          engine_token_id = None;
          engine_promote = None;
          updating = false;
          fault = None;
          on_complete;
          on_pause;
          next_listener_id = 0;
          state_listeners = [];
        }

let id timeline = timeline.timeline_id
let state timeline = timeline.state
let current_time_ms timeline = timeline.current_time_ms
let duration_ms timeline = timeline.duration_ms

let progress timeline =
  if Float.equal timeline.duration_ms 0.0 then 1.0
  else
    Float.min 1.0
      (Float.max 0.0 (timeline.current_time_ms /. timeline.duration_ms))

let is_playing timeline = match timeline.state with Playing -> true | _ -> false
let is_complete timeline = match timeline.state with Completed -> true | _ -> false
let fault timeline = timeline.fault
let item_count timeline = List.length timeline.items

let ensure_mutable timeline phase =
  match timeline.fault, timeline.sync_parent, timeline.engine_owner with
  | Some _, _, _ -> Error Error.Timeline_faulted
  | None, Some parent, _ -> Error (Error.Synchronized_child parent.parent.timeline_id)
  | None, None, Some engine -> Error (Error.Engine_owned engine)
  | None, None, None when timeline.updating -> Error Error.Busy
  | None, None, None ->
      ignore phase;
      Ok ()

let add timeline ~bindings ?(start_time_ms = 0.0) ?(duration_ms = 1000.0)
    ?(easing = Easing.linear) ?(loops = Once) ?(loop_delay_ms = 0.0)
    ?(alternate = false) ?(once = false) ?on_update ?on_start ?on_loop
    ?on_complete () =
  match ensure_mutable timeline Error.Add with
  | Error error -> Error error
  | Ok () ->
      match finite "start offset" start_time_ms with
      | Error error -> Error error
      | Ok () ->
          match nonnegative "item duration" duration_ms with
          | Error error -> Error error
          | Ok () ->
              match nonnegative "loop delay" loop_delay_ms with
              | Error error -> Error error
              | Ok () ->
                  match validate_loops loops with
                  | Error error -> Error error
                  | Ok () ->
                      match validate_bindings bindings with
                      | Error error -> Error error
                      | Ok () ->
                          let item_id = timeline.next_item_id in
                          timeline.next_item_id <- item_id + 1;
                          timeline.items <-
                            timeline.items
                            @ [ Numeric
                                  {
                                    id = item_id;
                                    start_time_ms;
                                    duration_ms;
                                    easing;
                                    loops;
                                    loop_delay_ms;
                                    alternate;
                                    once;
                                    bindings;
                                    initial_values = None;
                                    started = false;
                                    completed = false;
                                    last_cycle = -1;
                                    on_update;
                                    on_start;
                                    on_loop;
                                    on_complete;
                                  } ];
                          Ok item_id

let once timeline ~bindings ?start_time_ms ?duration_ms ?easing ?loops
    ?loop_delay_ms ?alternate ?on_update ?on_start ?on_loop ?on_complete () =
  add timeline ~bindings ?start_time_ms ?duration_ms ?easing ?loops
    ?loop_delay_ms ?alternate ~once:true ?on_update ?on_start ?on_loop
    ?on_complete ()

let call timeline ?(start_time_ms = 0.0) callback =
  match ensure_mutable timeline Error.Call with
  | Error error -> Error error
  | Ok () ->
      (match finite "callback start offset" start_time_ms with
      | Error error -> Error error
      | Ok () ->
          let item_id = timeline.next_item_id in
          timeline.next_item_id <- item_id + 1;
          timeline.items <-
            timeline.items
            @ [ Callback { id = item_id; start_time_ms; callback; called = false } ];
          Ok item_id)

let rec contains timeline target =
  if timeline == target then true
  else List.exists (fun token -> contains token.child target) timeline.sync_children

let sync parent child ?(start_time_ms = 0.0) () =
  match ensure_mutable parent Error.Sync with
  | Error error -> Error error
  | Ok () when parent == child -> Error Error.Parent_cycle
  | Ok () when contains child parent -> Error Error.Parent_cycle
  | Ok () ->
      (match finite "sync start offset" start_time_ms with
      | Error error -> Error error
      | Ok () ->
          (match child.engine_owner with
          | Some engine -> Error (Error.Engine_owned engine)
          | None ->
              (match child.sync_parent with
              | Some token -> Error (Error.Already_synchronized)
              | None ->
                  let token_id = parent.next_sync_id in
                  parent.next_sync_id <- token_id + 1;
                  let token =
                    {
                      parent;
                      child;
                      offset_ms = start_time_ms;
                      token_id;
                      started = false;
                      active = true;
                    }
                  in
                  parent.sync_children <- parent.sync_children @ [ token ];
                  child.sync_parent <- Some token;
                  Ok token)))

let cancel_sync token =
  if not token.active then Ok ()
  else begin
    token.active <- false;
    token.parent.sync_children <-
      List.filter (fun current -> current != token) token.parent.sync_children;
    (match token.child.sync_parent with
    | Some current when current == token -> token.child.sync_parent <- None
    | Some _ | None -> ());
    (match token.child.engine_promote with
    | Some promote -> promote token.child
    | None -> ());
    Ok ()
  end

let play_synchronized_children timeline =
  List.iter
    (fun token ->
      if token.active && token.started then
        match token.child.state with
        | Faulted | Completed -> ()
        | Idle | Playing | Paused -> set_state token.child Playing)
    timeline.sync_children

let reset_items timeline =
  List.iter
    (function
      | Numeric item ->
          item.started <- false;
          item.completed <- false;
          item.last_cycle <- -1
      | Callback item -> item.called <- false)
    timeline.items

let rec reset_synchronized_children timeline =
  List.iter
    (fun token ->
      if token.active then begin
        token.started <- false;
        reset_items token.child;
        token.child.current_time_ms <- 0.0;
        token.child.fault <- None;
        set_state token.child Paused;
        reset_synchronized_children token.child
      end)
    timeline.sync_children

let play timeline =
  match timeline.fault with
  | Some _ -> Error Error.Timeline_faulted
  | None ->
      (match timeline.sync_parent with
      | Some parent -> Error (Error.Synchronized_child parent.parent.timeline_id)
      | None ->
          (match timeline.state with
          | Playing -> Ok ()
          | Completed ->
              timeline.current_time_ms <- 0.0;
              reset_items timeline;
              reset_synchronized_children timeline;
              set_state timeline Playing;
              Ok ()
          | Idle | Paused ->
              set_state timeline Playing;
              play_synchronized_children timeline;
              Ok ()
          | Faulted -> Error Error.Timeline_faulted))

let pause timeline =
  match timeline.fault with
  | Some _ -> Error Error.Timeline_faulted
  | None ->
      (match timeline.sync_parent with
      | Some parent -> Error (Error.Synchronized_child parent.parent.timeline_id)
      | None ->
          (match timeline.state with
          | Playing | Paused | Idle ->
              set_state timeline Paused;
              List.iter
                (fun token ->
                  if token.active then
                    match token.child.state with
                    | Faulted | Completed -> ()
                    | Idle | Playing | Paused -> set_state token.child Paused)
                timeline.sync_children;
              (match timeline.on_pause with
              | None -> Ok ()
              | Some callback ->
                  (try callback (); Ok () with
                  | exception_value ->
                      (match
                         callback_failure timeline Error.On_pause exception_value
                       with
                      | Error fault -> Error (Error.Fault fault)
                      | Ok () -> Ok ())))
          | Completed -> Ok ()
          | Faulted -> Error Error.Timeline_faulted))

let restart timeline =
  match ensure_mutable timeline Error.Restart with
  | Error error -> Error error
  | Ok () ->
      timeline.current_time_ms <- 0.0;
      timeline.fault <- None;
      reset_items timeline;
      reset_synchronized_children timeline;
      set_state timeline Playing;
      Ok ()

let total_cycles (item : numeric_item) =
  match item.loops with
  | Once -> 1
  | Count count -> count
  | Infinite -> max_int

let item_elapsed (item : numeric_item) time = time -. item.start_time_ms

let cycle_and_progress (item : numeric_item) elapsed =
  if Float.compare elapsed 0.0 < 0 then None
  else if Float.equal item.duration_ms 0.0 then Some (0, 1.0, true)
  else
    let cycle_length = item.duration_ms +. item.loop_delay_ms in
    let cycle = int_of_float (Float.floor (elapsed /. cycle_length)) in
    let within = elapsed -. (float_of_int cycle *. cycle_length) in
    let complete = Int.compare cycle (total_cycles item) >= 0 in
    if complete then Some (total_cycles item - 1, 1.0, true)
    else if Float.compare within item.duration_ms >= 0 then
      Some (cycle, 1.0, false)
    else Some (cycle, within /. item.duration_ms, false)

let rec nth_float index values =
  match values with
  | [] -> None
  | value :: _ when Int.equal index 0 -> Some value
  | _ :: rest -> nth_float (index - 1) rest

let initialize_numeric timeline (item : numeric_item) =
  if item.started then Ok ()
  else begin
    item.started <- true;
    match validate_bindings item.bindings with
    | Error error ->
        fail timeline ~item_id:item.id Error.Read_property
          (Error.Structured error)
    | Ok () ->
        let start_result () =
          match item.on_start with
          | None -> Ok ()
          | Some callback ->
              (try callback (); Ok () with
              | exception_value ->
                  callback_failure timeline ~item_id:item.id Error.On_start
                    exception_value)
        in
        (match item.initial_values with
        | Some _ -> start_result ()
        | None ->
            let first_error = ref None in
            let read_exception = ref None in
            let values = ref [] in
            List.iter
              (fun binding ->
                match !first_error, !read_exception with
                | Some _, _ | _, Some _ -> ()
                | None, None ->
                    (try
                       match Property.Private.read binding with
                       | Ok value -> values := !values @ [ value ]
                       | Error error -> first_error := Some error
                     with
                    | exception_value -> read_exception := Some exception_value))
              item.bindings;
            (match !read_exception, !first_error with
            | Some exception_value, _ ->
                callback_failure timeline ~item_id:item.id Error.Read_property
                  exception_value
            | None, Some error ->
                fail timeline ~item_id:item.id Error.Read_property
                  (Error.Structured error)
            | None, None ->
                item.initial_values <- Some !values;
                start_result ()))
  end

let apply_numeric timeline (item : numeric_item) time delta_time_ms =
  match cycle_and_progress item (item_elapsed item time) with
  | None -> Ok false
  | Some (cycle, raw_progress, terminal) ->
      (match initialize_numeric timeline item with
      | Error fault -> Error fault
      | Ok () when item.completed -> Ok false
      | Ok () ->
          let eased = Easing.apply item.easing raw_progress in
          let progress =
            if item.alternate && Int.equal (Int.rem cycle 2) 1 then 1.0 -. eased
            else eased
          in
          let writes_error = ref None in
          let write_exception = ref None in
          let () =
            match item.initial_values with
            | None -> ()
            | Some initial_values ->
                let index = ref 0 in
                List.iter
                  (fun binding ->
                    let current_index = !index in
                    incr index;
                    match
                      !writes_error, !write_exception,
                      nth_float current_index initial_values
                    with
                    | Some _, _, _ | _, Some _, _ | _, _, None -> ()
                    | None, None, Some initial ->
                        let value =
                          initial
                          +. ((Property.Private.target_value binding -. initial)
                             *. progress)
                        in
                        (try
                           match Property.Private.write binding value with
                           | Ok () -> ()
                           | Error error ->
                               writes_error :=
                                 Some
                                   (make_fault ~item_id:item.id
                                      ~binding_index:current_index timeline
                                      Error.Write_property
                                      (Error.Structured error))
                         with
                        | exception_value ->
                            write_exception :=
                              Some
                                (make_fault ~item_id:item.id
                                   ~binding_index:current_index timeline
                                   Error.Write_property
                                   (Error.Exception
                                      (Error.exception_info exception_value))))
                  ) item.bindings
          in
          (match !writes_error, !write_exception with
          | Some value, _ | None, Some value ->
              timeline.fault <- Some value;
              set_state timeline Faulted;
              Error value
          | None, None ->
              let loop_result =
                if Int.compare cycle item.last_cycle > 0
                   && Int.compare item.last_cycle 0 >= 0
                then
                  match item.on_loop with
                  | None -> Ok ()
                  | Some callback ->
                      (try callback (); Ok () with
                      | exception_value ->
                          callback_failure timeline ~item_id:item.id Error.On_loop
                            exception_value)
                else Ok ()
              in
              (match loop_result with
              | Error fault -> Error fault
              | Ok () ->
              item.last_cycle <- cycle;
              let update_result =
                match item.on_update with
                | None -> Ok ()
                | Some callback ->
                    (try
                       callback
                         {
                           progress;
                           current_time_ms = time;
                           delta_time_ms;
                         };
                       Ok ()
                     with
                    | exception_value ->
                        callback_failure timeline ~item_id:item.id Error.On_update
                          exception_value)
              in
              (match update_result with
              | Error fault -> Error fault
              | Ok () when terminal ->
                  item.completed <- true;
                  (match item.on_complete with
                  | None -> Ok item.once
                  | Some callback ->
                      (try callback (); Ok item.once with
                      | exception_value ->
                          callback_failure timeline ~item_id:item.id
                            Error.On_complete exception_value))
              | Ok () -> Ok false))))

let apply_callback timeline item time =
  if not item.called && Float.compare time item.start_time_ms >= 0 then begin
    item.called <- true;
    try item.callback (); Ok true with
    | exception_value -> callback_failure timeline ~item_id:item.id Error.Callback exception_value
  end else Ok false

let rec reset_for_loop timeline =
  timeline.current_time_ms <- 0.0;
  List.iter
    (function
      | Numeric item ->
          item.started <- false;
          item.completed <- false;
          item.last_cycle <- -1
      | Callback item -> item.called <- false)
    timeline.items;
  List.iter
    (fun token ->
      if token.active then begin
        token.started <- false;
        reset_for_loop token.child;
        match token.child.state with
        | Faulted | Paused -> ()
        | Idle | Playing | Completed -> set_state token.child Paused
      end)
    timeline.sync_children

let update_child ~engine_update timeline token ~previous_time_ms
    ~target_time_ms ~delta_time_ms =
  if not token.active || Float.compare target_time_ms token.offset_ms < 0 then Ok ()
  else begin
    let crossing_offset = Float.compare previous_time_ms token.offset_ms < 0 in
    if crossing_offset then begin
      token.started <- true;
      set_state token.child Playing;
    end else if not token.started then begin
      token.started <- true;
      set_state token.child Playing
    end else if
      match token.child.state with
      | Paused | Idle -> true
      | Playing | Completed | Faulted -> false
    then set_state token.child Playing;
    let child_delta_time_ms =
      if crossing_offset then
        target_time_ms -. token.offset_ms
      else delta_time_ms
    in
    if Float.compare child_delta_time_ms 0.0 < 0 then Ok ()
    else
      match engine_update token.child child_delta_time_ms with
      | Ok () -> Ok ()
      | Error fault ->
          fail timeline Error.Child_timeline
            (Error.Child_fault fault)
  end

let evaluate_segment ~engine_update timeline ~previous_time_ms
    ~target_time_ms ~delta_time_ms =
  timeline.current_time_ms <- target_time_ms;
  let result = ref (Ok ()) in
  List.iter
    (fun token ->
      match !result with
      | Error _ -> ()
      | Ok () ->
          (match
             update_child ~engine_update timeline token ~previous_time_ms
               ~target_time_ms ~delta_time_ms
           with
          | Ok () -> ()
          | Error fault -> result := Error fault))
    timeline.sync_children;
  let remove_ids = ref [] in
  List.iter
    (fun item ->
      match !result, item with
      | Error _, _ -> ()
      | Ok (), Numeric value ->
          (match apply_numeric timeline value target_time_ms delta_time_ms with
          | Error fault -> result := Error fault
          | Ok true -> remove_ids := value.id :: !remove_ids
          | Ok false -> ())
      | Ok (), Callback value ->
          (match apply_callback timeline value target_time_ms with
          | Error fault -> result := Error fault
          | Ok true -> remove_ids := value.id :: !remove_ids
          | Ok false -> ()))
    timeline.items;
  timeline.items <-
    List.filter
      (fun item ->
        let item_id =
          match item with Numeric value -> value.id | Callback value -> value.id
        in
        not (List.exists (Int.equal item_id) !remove_ids))
      timeline.items;
  !result

let rec update_internal timeline ~delta_time_ms ~from_owner =
  let admission =
    if timeline.updating then
      fail timeline Error.Ownership (Error.Structured Error.Busy)
    else if not from_owner then
      match timeline.sync_parent, timeline.engine_owner with
      | Some parent, _ ->
          fail timeline Error.Ownership
            (Error.Structured (Error.Synchronized_child parent.parent.timeline_id))
      | None, Some engine ->
          fail timeline Error.Ownership
            (Error.Structured (Error.Engine_owned engine))
      | None, None -> Ok ()
    else Ok ()
  in
  match admission with
  | Error fault -> Error fault
  | Ok () ->
      (match finite "update delta" delta_time_ms with
      | Error error ->
          fail timeline Error.Validation (Error.Structured error)
      | Ok () ->
          if Float.compare delta_time_ms 0.0 < 0 then Ok ()
          else
            match timeline.state with
            | Faulted ->
                fail timeline Error.Validation (Error.Structured Error.Timeline_faulted)
            | Idle | Paused | Completed -> Ok ()
            | Playing -> begin
                let previous_time_ms = timeline.current_time_ms in
                let requested_time_ms = previous_time_ms +. delta_time_ms in
                if not (Float.is_finite requested_time_ms) then
                  fail timeline Error.Validation
                    (Error.Structured
                       (Error.Invalid_number
                          { field = "current time"; value = requested_time_ms }))
                else begin
                  timeline.updating <- true;
                  let engine_update child child_delta_time_ms =
                    update_internal child ~delta_time_ms:child_delta_time_ms
                      ~from_owner:true
                  in
                  let result =
                    if timeline.loop
                       && Float.compare requested_time_ms timeline.duration_ms >= 0
                    then begin
                      let first_segment =
                        evaluate_segment ~engine_update timeline ~previous_time_ms
                          ~target_time_ms:timeline.duration_ms
                          ~delta_time_ms:(timeline.duration_ms -. previous_time_ms)
                      in
                      match first_segment with
                      | Error fault -> Error fault
                      | Ok () ->
                          let overshoot =
                            requested_time_ms -. timeline.duration_ms
                          in
                          reset_for_loop timeline;
                          let target_time_ms =
                            mod_float overshoot timeline.duration_ms
                          in
                          if Float.equal target_time_ms 0.0 then Ok ()
                          else
                            evaluate_segment ~engine_update timeline
                              ~previous_time_ms:0.0
                              ~target_time_ms ~delta_time_ms:target_time_ms
                    end else begin
                      let target_time_ms =
                        Float.min timeline.duration_ms requested_time_ms
                      in
                      evaluate_segment ~engine_update timeline ~previous_time_ms
                        ~target_time_ms ~delta_time_ms
                    end
                  in
                  timeline.updating <- false;
                  match result with
                  | Error fault -> Error fault
                  | Ok () when timeline.loop -> Ok ()
                  | Ok ()
                    when Float.compare timeline.current_time_ms
                           timeline.duration_ms >= 0 ->
                      set_state timeline Completed;
                      (match timeline.on_complete with
                      | None -> Ok ()
                      | Some callback ->
                          (try callback (); Ok () with
                          | exception_value ->
                              callback_failure timeline Error.On_complete
                                exception_value))
                  | Ok () -> Ok ()
                end
              end)

let update timeline ~delta_time_ms = update_internal timeline ~delta_time_ms ~from_owner:false

module Sync = struct
  type t = sync_token
  let cancel = cancel_sync
end

module Private = struct
  let id = id
  let subtree timeline = List.map (fun token -> token.child) timeline.sync_children
  let is_playing = is_playing
  let is_engine_root timeline ~engine_id =
    match timeline.engine_owner, timeline.sync_parent with
    | Some current, None -> Int.equal current engine_id
    | Some _, Some _ | None, _ -> false

  let add_state_listener timeline callback =
    let id = timeline.next_listener_id in
    timeline.next_listener_id <- id + 1;
    timeline.state_listeners <- timeline.state_listeners @ [ id, callback ];
    id

  let remove_state_listener timeline listener_id =
    timeline.state_listeners <-
      List.filter
        (fun (current, _) -> not (Int.equal current listener_id))
        timeline.state_listeners

  let rec engine_subtree timeline =
    timeline
    :: List.concat (List.map engine_subtree (subtree timeline))

  let attach_engine timeline ~engine_id ~token_id ~promote =
    match timeline.sync_parent with
    | Some parent -> Error (Error.Synchronized_child parent.parent.timeline_id)
    | None ->
        let nodes = engine_subtree timeline in
        let conflict = ref None in
        List.iter
          (fun node ->
            match !conflict, node.engine_owner, node.engine_token_id with
            | Some _, _, _ -> ()
            | None, None, _ -> ()
            | None, Some current, Some current_token
              when Int.equal current engine_id
                   && Int.equal current_token token_id -> ()
            | None, Some current, _ when Int.equal current engine_id ->
                conflict := Some (Error.Engine_owned current)
            | None, Some current, _ ->
                conflict :=
                  Some
                    (Error.Cross_engine
                       { parent_engine_id = current; child_engine_id = engine_id }))
          nodes;
        (match !conflict with
        | Some error -> Error error
        | None ->
            List.iter
              (fun node ->
                node.engine_owner <- Some engine_id;
                node.engine_token_id <- Some token_id;
                node.engine_promote <- Some promote)
              nodes;
            Ok ())

  let detach_engine timeline ~engine_id ~token_id =
    List.iter
      (fun node ->
        match node.engine_owner, node.engine_token_id with
        | Some current, Some current_token
          when Int.equal current engine_id && Int.equal current_token token_id ->
            node.engine_owner <- None;
            node.engine_token_id <- None;
            node.engine_promote <- None
        | Some _, Some _ | Some _, None | None, _ -> ())
      (engine_subtree timeline)

  let engine_update timeline ~engine_id ~delta_time_ms =
    match timeline.engine_owner with
    | Some current when Int.equal current engine_id ->
        update_internal timeline ~delta_time_ms ~from_owner:true
    | Some _ -> fail timeline Error.Ownership (Error.Structured (Error.Cross_engine { parent_engine_id = engine_id; child_engine_id = -1 }))
    | None -> fail timeline Error.Ownership (Error.Structured (Error.Engine_destroyed))
end
