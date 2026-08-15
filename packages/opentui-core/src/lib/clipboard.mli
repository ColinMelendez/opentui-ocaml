type selection = Clipboard | Primary
type destination = Terminal_only | Host_only | Best_available | All_available
type capability = Supported | Unsupported | Unknown

type representation = { mime_type : string; bytes : bytes }

type host_status =
  | Written
  | Cleared
  | Empty
  | Host_unsupported
  | Not_attempted
  | Cancelled
  | Timed_out
  | Host_failed of string

type terminal_status =
  | Attempted
  | Local_failure of string
  | Not_attempted

type read_error =
  | Read_disposed
  | Invalid_preferred_types
  | Read_empty
  | Read_failed of host_status

type error =
  | Disposed
  | Invalid_selection
  | Invalid_destination
  | Empty_text
  | Nul_byte
  | Invalid_utf8
  | Limit_exceeded

type host = {
  max_write_bytes : int;
  read : preferred_types:string list -> selection:selection -> (representation option, host_status) result;
  write_text : selection:selection -> string -> host_status;
  clear : selection:selection -> host_status;
  dispose : unit -> unit;
}

type terminal = {
  remote : bool;
  capability : capability;
  write : bytes -> (unit, string) result;
}

type t

val create : host:host -> terminal:terminal -> unit -> t
val read :
  t ->
  preferred_types:string list ->
  ?selection:selection ->
  unit ->
  (representation, read_error) result
val write_text :
  t ->
  destination:destination ->
  ?selection:selection ->
  ?allow_remote_host:bool ->
  string ->
  ((host_status * terminal_status), error) result
val clear :
  t ->
  destination:destination ->
  ?selection:selection ->
  ?allow_remote_host:bool ->
  unit ->
  ((host_status * terminal_status), error) result
val osc52 : selection:selection -> string -> bytes
val osc52_clear : selection:selection -> bytes
val capability : t -> capability
val dispose : t -> unit
val validate_text : max_bytes:int -> string -> (unit, error) result
val message : error -> string
