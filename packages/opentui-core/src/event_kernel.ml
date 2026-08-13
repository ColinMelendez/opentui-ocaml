type 'a listener = {
  id : int;
  callback : 'a -> unit;
  once : bool;
  subscription : Event_subscription.t;
}

type 'a t = {
  mutable listeners : 'a listener array;
  mutable next_id : int;
}

let create () = { listeners = [||]; next_id = 0 }

let remove channel id =
  let current = channel.listeners in
  let retained =
    Array.to_list current
    |> List.filter (fun listener -> not (Int.equal listener.id id))
  in
  if not (Int.equal (List.length retained) (Array.length current)) then
    channel.listeners <- Array.of_list retained

let add channel ~once ~prepend callback =
  let id = channel.next_id in
  channel.next_id <- channel.next_id + 1;
  let subscription =
    Event_subscription.Private.create (fun () -> remove channel id)
  in
  let listener = { id; callback; once; subscription } in
  if prepend then
    channel.listeners <- Array.append [| listener |] channel.listeners
  else
    channel.listeners <- Array.append channel.listeners [| listener |];
  subscription

let on channel callback = add channel ~once:false ~prepend:false callback
let once channel callback = add channel ~once:true ~prepend:false callback
let prepend channel callback = add channel ~once:false ~prepend:true callback

let emit channel value =
  let snapshot = channel.listeners in
  let has_listeners = Array.length snapshot > 0 in
  let index = ref 0 in
  while !index < Array.length snapshot do
    let listener = snapshot.(!index) in
    if listener.once then Event_subscription.cancel listener.subscription;
    listener.callback value;
    index := !index + 1
  done;
  has_listeners

let listener_count channel = Array.length channel.listeners

let clear channel = channel.listeners <- [||]
