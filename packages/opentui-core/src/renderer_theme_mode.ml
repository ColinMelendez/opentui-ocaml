type mode = Light | Dark
type response = { handled : bool; changed_mode : mode option }

type waiter = { id : int; mutable timer : Lib.Clock.timer option; mutable cancelled : bool }

type t = {
  clock : Lib.Clock.t option;
  query : unit -> unit;
  mutable current : mode option;
  mutable query_pending : bool;
  mutable foreground : (int * int * int) option;
  mutable background : (int * int * int) option;
  mutable refresh_timer : Lib.Clock.timer option;
  mutable next_id : int;
  mutable waiters : (waiter * (mode option -> unit)) list;
  mutable disposed : bool;
}

let query_sequence = "\027]10;?\007\027]11;?\007"
let mode_name = function Light -> "light" | Dark -> "dark"

let create_with_clock ~clock ~query () =
  { clock; query; current = None; query_pending = false; foreground = None;
    background = None; refresh_timer = None; next_id = 1; waiters = []; disposed = false }

let create ~clock ~query () = create_with_clock ~clock:(Some clock) ~query ()

let create_without_clock ~query () =
  create_with_clock ~clock:None ~query ()

let mode owner = owner.current

let clear_refresh owner =
  (match owner.clock with
  | None -> ()
  | Some clock -> Option.iter (Lib.Clock.cancel clock) owner.refresh_timer);
  owner.refresh_timer <- None

let complete_query owner =
  clear_refresh owner;
  owner.query_pending <- false

let apply_mode owner next =
  let changed =
    match owner.current, next with
    | Some Light, Light | Some Dark, Dark -> false
    | Some _, _ | None, _ -> true
  in
  owner.current <- Some next;
  if changed then begin
    let waiters = owner.waiters in
    owner.waiters <- [];
    List.iter
      (fun (waiter, callback) ->
        if not waiter.cancelled then begin
          (match owner.clock with
          | None -> ()
          | Some clock -> Option.iter (Lib.Clock.cancel clock) waiter.timer);
          callback (Some next)
        end)
      waiters
  end;
  if changed then Some next else None

let request owner =
  if not owner.disposed && not owner.query_pending
     && Option.is_none owner.refresh_timer then begin
    owner.query_pending <- true;
    owner.foreground <- None;
    owner.background <- None;
    owner.refresh_timer <-
      (match owner.clock with
      | None -> None
      | Some clock ->
          Some
            (Lib.Clock.schedule clock ~delay:0.25 (fun () -> complete_query owner)));
    owner.query ()
  end

let hex_digit character =
  let code = Char.code character in
  if code >= Char.code '0' && code <= Char.code '9' then Some (code - Char.code '0')
  else if code >= Char.code 'a' && code <= Char.code 'f' then Some (code - Char.code 'a' + 10)
  else if code >= Char.code 'A' && code <= Char.code 'F' then Some (code - Char.code 'A' + 10)
  else None

let scaled_component source =
  if String.length source = 0 || String.length source > 8 then None
  else
    let value = ref 0 in
    let maximum = ref 0 in
    let valid = ref true in
    for index = 0 to String.length source - 1 do
      match hex_digit (String.get source index) with
      | None -> valid := false
      | Some digit ->
          if !value > (Int.max_int - digit) / 16 then valid := false
          else begin value := (!value * 16) + digit; maximum := (!maximum * 16) + 15 end
    done;
    if not !valid || Int.equal !maximum 0 then None
    else Some (int_of_float (Float.round (float_of_int !value *. 255.0 /. float_of_int !maximum)))

let color payload =
  if String.length payload = 7 && Char.equal (String.get payload 0) '#' then
    let component offset = scaled_component (String.sub payload offset 2) in
    (match component 1, component 3, component 5 with Some r, Some g, Some b -> Some (r, g, b) | _ -> None)
  else if String.length payload > 4 && String.equal (String.sub payload 0 4) "rgb:" then
    (match String.split_on_char '/' (String.sub payload 4 (String.length payload - 4)) with
    | [ r; g; b ] ->
        (match scaled_component r, scaled_component g, scaled_component b with Some r, Some g, Some b -> Some (r, g, b) | _ -> None)
    | _ -> None)
  else None

let parse_response_body owner body =
  match String.index_opt body ';' with
  | None -> false
  | Some separator ->
      let code = String.sub body 0 separator in
      let payload = String.sub body (separator + 1) (String.length body - separator - 1) in
      (match color payload with
      | None -> false
      | Some value when String.equal code "10" -> owner.foreground <- Some value; true
      | Some value when String.equal code "11" -> owner.background <- Some value; true
      | Some _ -> false)

let infer = function
  | r, g, b when ((r * 299) + (g * 587) + (b * 114)) > 128000 -> Light
  | _ -> Dark

let rec find_osc source start =
  match String.index_from_opt source start '\027' with
  | None -> None
  | Some position when position + 1 >= String.length source -> None
  | Some position when not (Char.equal (String.get source (position + 1)) ']') -> find_osc source (position + 1)
  | Some position ->
      let cursor = ref (position + 2) in
      let terminator = ref None in
      while !cursor < String.length source && Option.is_none !terminator do
        if Char.equal (String.get source !cursor) '\007' then terminator := Some (!cursor, 1)
        else if Char.equal (String.get source !cursor) '\027'
                && !cursor + 1 < String.length source
                && Char.equal (String.get source (!cursor + 1)) '\\'
        then terminator := Some (!cursor, 2)
        else incr cursor
      done;
      Option.map (fun (finish, width) -> position, String.sub source (position + 2) (finish - position - 2), finish + width) !terminator

let handle_sequence owner sequence =
  if owner.disposed then { handled = false; changed_mode = None }
  else if String.equal sequence "\027[?997;1n" || String.equal sequence "\027[?997;2n" then begin
    request owner;
    { handled = true; changed_mode = None }
  end
  else
    let cursor = ref 0 in
    let handled = ref false in
    while !cursor < String.length sequence do
      match find_osc sequence !cursor with
      | None -> cursor := String.length sequence
      | Some (_, body, next) ->
          if parse_response_body owner body then handled := true;
          cursor := next
    done;
    match !handled, owner.query_pending, owner.foreground, owner.background with
    | true, true, Some _, Some background ->
        let changed_mode = apply_mode owner (infer background) in
        complete_query owner;
        { handled = true; changed_mode }
    | handled, _, _, _ -> { handled; changed_mode = None }

let wait_for owner ~timeout_ms ~on_result =
  let id = owner.next_id in
  owner.next_id <- id + 1;
  let waiter = { id; timer = None; cancelled = false } in
  let immediate_without_clock =
    Int.compare timeout_ms 0 > 0 && Option.is_none owner.clock
  in
  if owner.disposed || Option.is_some owner.current
     || Int.equal timeout_ms 0 || immediate_without_clock then begin
    waiter.cancelled <- true;
    on_result owner.current
  end
  else begin
    let timer =
      if Int.compare timeout_ms 0 > 0 then
        (match owner.clock with
        | None -> None
        | Some clock ->
            Some
              (Lib.Clock.schedule clock
                 ~delay:(float_of_int timeout_ms /. 1000.0)
                 (fun () ->
                   if not waiter.cancelled then begin
                     waiter.cancelled <- true;
                     owner.waiters <-
                       List.filter
                         (fun (entry, _) -> not (Int.equal entry.id id))
                         owner.waiters;
                     on_result owner.current
                   end)))
      else None
    in
    waiter.timer <- timer;
    owner.waiters <- (waiter, on_result) :: owner.waiters
  end;
  waiter

let cancel_wait owner waiter =
  if not waiter.cancelled then begin
    waiter.cancelled <- true;
    (match owner.clock with
    | None -> ()
    | Some clock -> Option.iter (Lib.Clock.cancel clock) waiter.timer);
    owner.waiters <- List.filter (fun (entry, _) -> not (Int.equal entry.id waiter.id)) owner.waiters
  end

let cancel_refresh owner =
  clear_refresh owner;
  owner.query_pending <- false

let dispose owner =
  if not owner.disposed then begin
    owner.disposed <- true;
    cancel_refresh owner;
    List.iter
      (fun (waiter, callback) ->
        waiter.cancelled <- true;
        (match owner.clock with
        | None -> ()
        | Some clock -> Option.iter (Lib.Clock.cancel clock) waiter.timer);
        callback owner.current)
      owner.waiters;
    owner.waiters <- []
  end
