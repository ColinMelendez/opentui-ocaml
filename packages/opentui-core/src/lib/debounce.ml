type entry = { id : string; token : int; timer : Clock.timer }

type t = {
  clock : Clock.t;
  mutable next_token : int;
  mutable entries : entry list;
}

let create ~clock () = { clock; next_token = 1; entries = [] }

let remove_token owner token =
  owner.entries <- List.filter (fun entry -> not (Int.equal entry.token token)) owner.entries

let cancel owner ~id =
  List.iter
    (fun entry -> if String.equal entry.id id then Clock.cancel owner.clock entry.timer)
    owner.entries;
  owner.entries <- List.filter (fun entry -> not (String.equal entry.id id)) owner.entries

let debounce owner ~id ~delay callback =
  cancel owner ~id;
  let token = owner.next_token in
  owner.next_token <- token + 1;
  let timer =
    Clock.schedule owner.clock ~delay (fun () ->
        match List.find_opt (fun entry -> Int.equal entry.token token) owner.entries with
        | None -> ()
        | Some _ ->
            remove_token owner token;
            callback ())
  in
  owner.entries <- { id; token; timer } :: owner.entries

let clear owner =
  List.iter (fun entry -> Clock.cancel owner.clock entry.timer) owner.entries;
  owner.entries <- []

let size owner = List.length owner.entries
