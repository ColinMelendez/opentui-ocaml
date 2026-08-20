type t =
  | Closed of { operation : string }
  | Invalid_argument of string
  | Creation_failed of {
      what : string;
      code : int;
      message : string;
    }
  | Map_failed of { code : int; message : string }
  | Native_failure of { operation : string }

let pp formatter = function
  | Closed { operation } ->
      Format.fprintf formatter "device closed before %s" operation
  | Invalid_argument detail ->
      Format.fprintf formatter "invalid argument: %s" detail
  | Creation_failed { what; code; message } ->
      Format.fprintf formatter "%s creation failed (code %d): %s" what code
        message
  | Map_failed { code; message } ->
      Format.fprintf formatter "buffer map failed (code %d): %s" code message
  | Native_failure { operation } ->
      Format.fprintf formatter "native operation failed: %s" operation

let message error = Format.asprintf "%a" pp error
