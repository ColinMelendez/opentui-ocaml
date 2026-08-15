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
type terminal_status = Attempted | Local_failure of string | Not_attempted
type read_error = Read_disposed | Invalid_preferred_types | Read_empty | Read_failed of host_status
type error = Disposed | Invalid_selection | Invalid_destination | Empty_text | Nul_byte | Invalid_utf8 | Limit_exceeded

type host = {
  max_write_bytes : int;
  read : preferred_types:string list -> selection:selection -> (representation option, host_status) result;
  write_text : selection:selection -> string -> host_status;
  clear : selection:selection -> host_status;
  dispose : unit -> unit;
}

type terminal = { remote : bool; capability : capability; write : bytes -> (unit, string) result }

type t = { host : host; terminal : terminal; mutable disposed : bool }

let create ~host ~terminal () =
  let host = { host with max_write_bytes = Int.max 0 host.max_write_bytes } in
  { host; terminal; disposed = false }

let valid_utf8 source =
  let length = String.length source in
  let continuation value = Int.equal (value land 0xc0) 0x80 in
  let valid = ref true in
  let index = ref 0 in
  while !valid && Int.compare !index length < 0 do
    let first = Char.code (String.get source !index) in
    let needed, second_min, second_max =
      if Int.compare first 0x80 < 0 then 0, 0, 0
      else if Int.compare first 0xc2 >= 0 && Int.compare first 0xdf <= 0 then
        1, 0x80, 0xbf
      else if Int.equal first 0xe0 then 2, 0xa0, 0xbf
      else if Int.compare first 0xe1 >= 0 && Int.compare first 0xec <= 0 then
        2, 0x80, 0xbf
      else if Int.equal first 0xed then 2, 0x80, 0x9f
      else if Int.compare first 0xee >= 0 && Int.compare first 0xef <= 0 then
        2, 0x80, 0xbf
      else if Int.equal first 0xf0 then 3, 0x90, 0xbf
      else if Int.compare first 0xf1 >= 0 && Int.compare first 0xf3 <= 0 then
        3, 0x80, 0xbf
      else if Int.equal first 0xf4 then 3, 0x80, 0x8f
      else -1, 0, 0
    in
    if Int.equal needed (-1) || Int.compare (!index + needed) length >= 0 then valid := false
    else begin
      if Int.compare needed 1 >= 0 then begin
        let second = Char.code (String.get source (!index + 1)) in
        if Int.compare second second_min < 0
           || Int.compare second second_max > 0
           || not (continuation second) then valid := false
      end;
      for offset = 2 to needed do
        if not (continuation (Char.code (String.get source (!index + offset)))) then
          valid := false
      done;
      if !valid then index := length else index := !index + needed + 1
    end
  done;
  !valid

let validate_text ~max_bytes text =
  if String.length text = 0 then Error Empty_text
  else if String.contains text '\000' then Error Nul_byte
  else if not (valid_utf8 text) then Error Invalid_utf8
  else if String.length text > max_bytes then Error Limit_exceeded
  else Ok ()

let base64_table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

let base64 source =
  let length = String.length source in
  let output = Bytes.create (((length + 2) / 3) * 4) in
  let output_index = ref 0 in
  let set value = Bytes.set output !output_index (String.get base64_table value); output_index := !output_index + 1 in
  let index = ref 0 in
  while Int.compare !index length < 0 do
    let first = Char.code (String.get source !index) in
    let remaining = length - !index in
    let second = if Int.compare remaining 1 > 0 then Char.code (String.get source (!index + 1)) else 0 in
    let third = if Int.compare remaining 2 > 0 then Char.code (String.get source (!index + 2)) else 0 in
    set (first lsr 2);
    set (((first land 3) lsl 4) lor (second lsr 4));
    if Int.compare remaining 1 > 0 then set (((second land 15) lsl 2) lor (third lsr 6)) else (Bytes.set output !output_index '='; output_index := !output_index + 1);
    if Int.compare remaining 2 > 0 then set (third land 63) else (Bytes.set output !output_index '='; output_index := !output_index + 1);
    index := !index + 3
  done;
  output

let target = function Clipboard -> "c" | Primary -> "p"
let osc52 ~selection text =
  Bytes.of_string ("\027]52;" ^ target selection ^ ";" ^ Bytes.to_string (base64 text) ^ "\007")
let osc52_clear ~selection = osc52 ~selection ""

let validate_destination = function
  | Terminal_only | Host_only | Best_available | All_available -> true

let validate_selection = function Clipboard | Primary -> true

let valid_preferred_types preferred_types =
  match preferred_types with
  | [] -> false
  | first :: rest ->
      String.length first > 0
      && List.for_all (fun mime -> String.length mime > 0) rest

let read owner ~preferred_types ?(selection = Clipboard) () =
  if owner.disposed then Error Read_disposed
  else if not (validate_selection selection) || not (valid_preferred_types preferred_types) then
    Error Invalid_preferred_types
  else
    match owner.host.read ~preferred_types ~selection with
    | Ok (Some value) -> Ok value
    | Ok None -> Error Read_empty
    | Error error -> Error (Read_failed error)

let terminal_write owner ~selection text =
  match owner.terminal.capability with
  | Unsupported -> Not_attempted
  | Supported | Unknown ->
      (match owner.terminal.write (osc52 ~selection text) with Ok () -> Attempted | Error error -> Local_failure error)

let terminal_clear owner ~selection =
  match owner.terminal.capability with
  | Unsupported -> Not_attempted
  | Supported | Unknown ->
      (match owner.terminal.write (osc52_clear ~selection) with Ok () -> Attempted | Error error -> Local_failure error)

let write_text owner ~destination ?(selection = Clipboard) ?(allow_remote_host = false) text =
  if owner.disposed then Error Disposed
  else if not (validate_destination destination) then Error Invalid_destination
  else
    Result.bind (validate_text ~max_bytes:owner.host.max_write_bytes text) (fun () ->
        let host_allowed = (not owner.terminal.remote) || allow_remote_host in
        let host_result () : host_status =
          if host_allowed then owner.host.write_text ~selection text
          else (Not_attempted : host_status)
        in
        match destination with
        | Terminal_only ->
            Ok ((Not_attempted : host_status), terminal_write owner ~selection text)
        | Host_only -> Ok (host_result (), (Not_attempted : terminal_status))
        | Best_available ->
            if owner.terminal.remote then
              Ok ((Not_attempted : host_status), terminal_write owner ~selection text)
            else
              let host = host_result () in
              let terminal =
                match host with Written -> Not_attempted | _ -> terminal_write owner ~selection text
              in
              Ok (host, terminal)
        | All_available -> Ok (host_result (), terminal_write owner ~selection text))

let clear owner ~destination ?(selection = Clipboard) ?(allow_remote_host = false) () =
  if owner.disposed then Error Disposed
  else if not (validate_destination destination) then Error Invalid_destination
  else
    let host_allowed = (not owner.terminal.remote) || allow_remote_host in
    let host_result () : host_status =
      if host_allowed then owner.host.clear ~selection
      else (Not_attempted : host_status)
    in
    match destination with
    | Terminal_only ->
        Ok ((Not_attempted : host_status), terminal_clear owner ~selection)
    | Host_only -> Ok (host_result (), (Not_attempted : terminal_status))
    | Best_available ->
        if owner.terminal.remote then
          Ok ((Not_attempted : host_status), terminal_clear owner ~selection)
        else
          let host = host_result () in
          let terminal = match host with Cleared -> Not_attempted | _ -> terminal_clear owner ~selection in
          Ok (host, terminal)
    | All_available -> Ok (host_result (), terminal_clear owner ~selection)

let capability owner = owner.terminal.capability

let dispose owner =
  if not owner.disposed then begin
    owner.disposed <- true;
    owner.host.dispose ()
  end

let message = function
  | Disposed -> "clipboard service is disposed"
  | Invalid_selection -> "clipboard selection is invalid"
  | Invalid_destination -> "clipboard destination is invalid"
  | Empty_text -> "clipboard text must not be empty"
  | Nul_byte -> "clipboard text must not contain NUL"
  | Invalid_utf8 -> "clipboard text must be valid UTF-8"
  | Limit_exceeded -> "clipboard text exceeds the configured byte limit"
