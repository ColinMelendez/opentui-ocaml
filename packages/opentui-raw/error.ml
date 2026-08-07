type t =
  | Invalid_argument
  | Closed
  | Stale_handle
  | Native_failure
  | Output_too_small
  | Queue_overflow
  | No_space
  | Max_bytes
  | Busy

let message = function
  | Invalid_argument -> "invalid argument"
  | Closed -> "the native owner is closed"
  | Stale_handle -> "the native handle is stale"
  | Native_failure -> "the native OpenTUI operation failed"
  | Output_too_small -> "the output buffer is too small"
  | Queue_overflow -> "the native event queue overflowed"
  | No_space -> "the native output feed has no writable space"
  | Max_bytes -> "the native output feed reached its byte limit"
  | Busy -> "the native output feed has an active operation"

let pp formatter error = Format.pp_print_string formatter (message error)

module Private = struct
  let of_native_status status =
    match status with
    | 0 -> None
    | 1 -> Some Invalid_argument
    | 2 -> Some Stale_handle
    | 3 -> Some Native_failure
    | 4 -> Some Output_too_small
    | 5 -> Some Queue_overflow
    | 6 -> Some No_space
    | 7 -> Some Max_bytes
    | 8 -> Some Busy
    | _ -> Some Native_failure
end
