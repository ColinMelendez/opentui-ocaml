type stream = Stdout | Stderr
type chunk = { stream : stream; output : string }

type error = Closed | Limit_exceeded | Flow_failed of string | Restore_failed of string

type t = {
  max_bytes : int;
  restore_action : unit -> (unit, string) result;
  mutable captured : chunk list;
  mutable byte_count : int;
  mutable closed : bool;
  mutable restored : bool;
}

let create ?(max_bytes = 1024 * 1024)
    ?(restore = fun () -> Ok ()) () =
  { max_bytes = Int.max 0 max_bytes;
    restore_action = restore;
    captured = [];
    byte_count = 0;
    closed = false;
    restored = false }

let write owner ~stream output =
  if owner.closed then Error Closed
  else if String.length output > owner.max_bytes - owner.byte_count then Error Limit_exceeded
  else begin
    owner.captured <- owner.captured @ [ { stream; output } ];
    owner.byte_count <- owner.byte_count + String.length output;
    Ok ()
  end

let size owner = List.length owner.captured
let bytes owner = owner.byte_count

let chunks owner = List.map (fun chunk -> { chunk with output = chunk.output }) owner.captured

let claim_output owner =
  let output = String.concat "" (List.map (fun chunk -> chunk.output) owner.captured) in
  owner.captured <- [];
  owner.byte_count <- 0;
  output

let restore owner =
  if owner.restored then Ok ()
  else begin
    match owner.restore_action () with
    | Ok () ->
        owner.restored <- true;
        Ok ()
    | Error message -> Error (Restore_failed message)
  end

let drain_to owner ~write =
  if owner.closed then Error Closed
  else
    let result = ref (Ok ()) in
    List.iter
      (fun chunk ->
        match !result with
        | Error _ -> ()
        | Ok () ->
            let bytes = Bytes.of_string chunk.output in
            let length = Bytes.length bytes in
            let offset = ref 0 in
            let can_continue () =
              match !result with
              | Ok () -> Int.compare !offset length < 0
              | Error _ -> false
            in
            while can_continue () do
              match write chunk.stream bytes ~off:!offset ~len:(length - !offset) with
              | Ok count when Int.compare count 0 > 0
                            && Int.compare count (length - !offset) <= 0 ->
                  offset := !offset + count
              | Ok _ ->
                  result := Error (Flow_failed "capture writer made no progress")
              | Error message -> result := Error (Flow_failed message)
            done)
      owner.captured;
    (match !result with Ok () -> ignore (claim_output owner) | Error _ -> ());
    !result

let close owner =
  if not owner.closed then begin
    ignore (restore owner);
    owner.closed <- true;
    owner.captured <- [];
    owner.byte_count <- 0
  end

let message = function
  | Closed -> "output capture is closed"
  | Limit_exceeded -> "output capture byte limit exceeded"
  | Flow_failed value -> "output capture flow failed: " ^ value
  | Restore_failed value -> "output capture restore failed: " ^ value
