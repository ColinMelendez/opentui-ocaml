type operation =
  | Create
  | Add
  | Once
  | Call
  | Sync
  | Play
  | Pause
  | Restart
  | Update
  | Register
  | Run_once
  | Release
  | Clear
  | Destroy

type failure_phase =
  | Validation
  | Ownership
  | Read_property
  | Write_property
  | Builtin_easing
  | On_start
  | On_update
  | On_loop
  | On_complete
  | On_pause
  | Callback
  | Child_timeline

type exception_info = {
  exception_name : string;
  backtrace : string option;
}

type t =
  | Invalid_number of { field : string; value : float }
  | Negative_number of { field : string; value : float }
  | Invalid_loop_count of int
  | Loop_requires_positive_duration
  | Busy
  | Engine_owned of int
  | Synchronized_child of int
  | Already_synchronized
  | Cross_engine of { parent_engine_id : int; child_engine_id : int }
  | Parent_cycle
  | Engine_destroyed
  | Timeline_faulted
  | Child_faulted of int
  | Fault of fault
  | Invalid_operation of operation
  | User of { code : string; detail : string option }

and cause =
  | Structured of t
  | Exception of exception_info
  | Non_finite_result of float
  | Child_fault of fault

and fault = {
  item_id : int option;
  binding_index : int option;
  timeline_time_ms : float;
  phase : failure_phase;
  cause : cause;
}

let user ?detail code = User { code; detail }

let exception_info exception_value =
  let backtrace = Printexc.get_backtrace () in
  {
    exception_name = Printexc.to_string exception_value;
    backtrace = if String.equal backtrace "" then None else Some backtrace;
  }

let operation_message = function
  | Create -> "create"
  | Add -> "add"
  | Once -> "once"
  | Call -> "call"
  | Sync -> "sync"
  | Play -> "play"
  | Pause -> "pause"
  | Restart -> "restart"
  | Update -> "update"
  | Register -> "register"
  | Run_once -> "run_once"
  | Release -> "release"
  | Clear -> "clear"
  | Destroy -> "destroy"

let message error =
  match error with
  | Invalid_number { field; value = _ } ->
      "animation value for " ^ field ^ " must be finite"
  | Negative_number { field; value = _ } ->
      "animation value for " ^ field ^ " must not be negative"
  | Invalid_loop_count count ->
      "animation loop count must be a positive integer (received "
      ^ string_of_int count ^ ")"
  | Loop_requires_positive_duration ->
      "a looping timeline must have a positive duration"
  | Busy -> "animation evaluation is already in progress"
  | Engine_owned id ->
      "timeline is owned by animation engine " ^ string_of_int id
  | Synchronized_child id ->
      "timeline is synchronized under parent timeline " ^ string_of_int id
  | Already_synchronized -> "timeline is already synchronized under a parent"
  | Cross_engine { parent_engine_id; child_engine_id } ->
      "timelines belong to different animation engines (parent "
      ^ string_of_int parent_engine_id ^ ", child " ^ string_of_int child_engine_id
      ^ ")"
  | Parent_cycle -> "synchronizing these timelines would create a cycle"
  | Engine_destroyed -> "animation engine is destroyed"
  | Timeline_faulted -> "timeline is faulted and must be restarted"
  | Child_faulted id ->
      "synchronized child timeline " ^ string_of_int id ^ " is faulted"
  | Fault _ -> "animation timeline faulted"
  | Invalid_operation operation ->
      "animation operation is invalid: " ^ operation_message operation
  | User { code; detail = None } -> "animation user error: " ^ code
  | User { code; detail = Some detail } ->
      "animation user error: " ^ code ^ ": " ^ detail

let pp formatter error = Format.pp_print_string formatter (message error)

let phase_message = function
  | Validation -> "validation"
  | Ownership -> "ownership"
  | Read_property -> "property read"
  | Write_property -> "property write"
  | Builtin_easing -> "easing"
  | On_start -> "on_start callback"
  | On_update -> "on_update callback"
  | On_loop -> "on_loop callback"
  | On_complete -> "on_complete callback"
  | On_pause -> "on_pause callback"
  | Callback -> "callback item"
  | Child_timeline -> "child timeline"

let rec cause_message cause =
  match cause with
  | Structured error -> message error
  | Exception info -> "exception: " ^ info.exception_name
  | Non_finite_result _ -> "callback or easing result was not finite"
  | Child_fault fault -> "child fault: " ^ fault_message fault

and fault_message fault =
  let item =
    match fault.item_id with
    | None -> ""
    | Some id -> " for item " ^ string_of_int id
  in
  "animation fault" ^ item ^ " during " ^ phase_message fault.phase ^ ": "
  ^ cause_message fault.cause

let fault_pp formatter fault = Format.pp_print_string formatter (fault_message fault)
