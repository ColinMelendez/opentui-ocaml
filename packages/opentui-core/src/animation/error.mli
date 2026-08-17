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

val user : ?detail:string -> string -> t
val exception_info : exn -> exception_info
val message : t -> string
val pp : Format.formatter -> t -> unit
val fault_message : fault -> string
val fault_pp : Format.formatter -> fault -> unit
