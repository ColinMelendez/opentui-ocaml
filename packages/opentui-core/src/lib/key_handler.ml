type event_kind = Keypress | Keyrelease | Paste

type key_event = {
  raw : bytes;
  key : Key_decoder.key;
  modifiers : Key_decoder.modifiers;
  kind : event_kind;
  mutable default_prevented : bool;
  mutable propagation_stopped : bool;
}

type paste_event = {
  raw : bytes;
  mutable default_prevented : bool;
  mutable propagation_stopped : bool;
}

type handler_scope = Global | Renderable

type handler_error = {
  kind : event_kind;
  scope : handler_scope;
  owner_num : int option;
  exception_value : exn;
}

type 'a listener = {
  id : int;
  callback : 'a -> unit;
  once : bool;
  subscription : Event_subscription.t;
}

type 'a channel = {
  mutable listeners : 'a listener array;
  mutable next_id : int;
}

type internal_key_listener = {
  owner_num : int;
  callback : key_event -> unit;
  subscription : Event_subscription.t;
}

type internal_paste_listener = {
  owner_num : int;
  callback : paste_event -> unit;
  subscription : Event_subscription.t;
}

type t = {
  keypress : key_event channel;
  keyrelease : key_event channel;
  paste : paste_event channel;
  mutable internal_keypress : internal_key_listener array;
  mutable internal_keyrelease : internal_key_listener array;
  mutable internal_paste : internal_paste_listener array;
  on_error : handler_error -> unit;
}

let remove_listener channel id =
  let current = channel.listeners in
  let retained =
    Array.to_list current
    |> List.filter (fun listener -> not (Int.equal listener.id id))
  in
  if not (Int.equal (List.length retained) (Array.length current)) then
    channel.listeners <- Array.of_list retained

let add_listener channel ?(once = false) ?(prepend = false) callback =
  let id = channel.next_id in
  channel.next_id <- id + 1;
  let subscription =
    Event_subscription.Private.create (fun () -> remove_listener channel id)
  in
  let listener = { id; callback; once; subscription } in
  channel.listeners <-
    if prepend then Array.append [| listener |] channel.listeners
    else Array.append channel.listeners [| listener |];
  subscription

let remove_key_by_subscription (listeners : internal_key_listener array)
    subscription =
  Array.to_list listeners
  |> List.filter
       (fun (listener : internal_key_listener) ->
         listener.subscription != subscription)
  |> Array.of_list

let remove_paste_by_subscription (listeners : internal_paste_listener array)
    subscription =
  Array.to_list listeners
  |> List.filter
       (fun (listener : internal_paste_listener) ->
         listener.subscription != subscription)
  |> Array.of_list

let create_channel () = { listeners = [||]; next_id = 0 }

let create ?(on_error = fun _ -> ()) () =
  {
    keypress = create_channel ();
    keyrelease = create_channel ();
    paste = create_channel ();
    internal_keypress = [||];
    internal_keyrelease = [||];
    internal_paste = [||];
    on_error;
  }

let key_raw (event : key_event) = event.raw
let key (event : key_event) = event.key
let key_modifiers (event : key_event) = event.modifiers
let key_event_kind (event : key_event) = event.kind
let paste_raw (event : paste_event) = event.raw

let default_prevented (event : key_event) = event.default_prevented
let stop_propagation (event : key_event) = event.propagation_stopped <- true
let prevent_default (event : key_event) = event.default_prevented <- true
let propagation_stopped (event : key_event) = event.propagation_stopped

let paste_default_prevented (event : paste_event) = event.default_prevented
let paste_stop_propagation (event : paste_event) = event.propagation_stopped <- true
let paste_prevent_default (event : paste_event) = event.default_prevented <- true
let paste_propagation_stopped (event : paste_event) = event.propagation_stopped

let on_keypress handler callback = add_listener handler.keypress callback
let once_keypress handler callback = add_listener handler.keypress ~once:true callback

let prepend_keypress handler callback =
  add_listener handler.keypress ~prepend:true callback

let on_keyrelease handler callback = add_listener handler.keyrelease callback

let once_keyrelease handler callback =
  add_listener handler.keyrelease ~once:true callback

let prepend_keyrelease handler callback =
  add_listener handler.keyrelease ~prepend:true callback

let on_paste handler callback = add_listener handler.paste callback
let once_paste handler callback = add_listener handler.paste ~once:true callback
let prepend_paste handler callback = add_listener handler.paste ~prepend:true callback

let on_internal_keypress handler ~owner_num callback =
  let subscription_ref = ref None in
  let subscription =
    Event_subscription.Private.create (fun () ->
        Option.iter
          (fun token ->
            handler.internal_keypress <-
              remove_key_by_subscription handler.internal_keypress token)
          !subscription_ref)
  in
  subscription_ref := Some subscription;
  handler.internal_keypress <-
    Array.append handler.internal_keypress
      [| { owner_num; callback; subscription } |];
  subscription

let on_internal_keyrelease handler ~owner_num callback =
  let subscription_ref = ref None in
  let subscription =
    Event_subscription.Private.create (fun () ->
        Option.iter
          (fun token ->
            handler.internal_keyrelease <-
              remove_key_by_subscription handler.internal_keyrelease token)
          !subscription_ref)
  in
  subscription_ref := Some subscription;
  handler.internal_keyrelease <-
    Array.append handler.internal_keyrelease
      [| { owner_num; callback; subscription } |];
  subscription

let on_internal_paste handler ~owner_num callback =
  let subscription_ref = ref None in
  let subscription =
    Event_subscription.Private.create (fun () ->
        Option.iter
          (fun token ->
            handler.internal_paste <-
              remove_paste_by_subscription handler.internal_paste token)
          !subscription_ref)
  in
  subscription_ref := Some subscription;
  handler.internal_paste <-
    Array.append handler.internal_paste
      [| { owner_num; callback; subscription } |];
  subscription

let report handler ~kind ~scope ~owner_num exception_value =
  handler.on_error { kind; scope; owner_num; exception_value }

let emit_global_key handler ~kind (channel : key_event channel)
    (event : key_event) ~stop =
  let snapshot = channel.listeners in
  let index = ref 0 in
  while Int.compare !index (Array.length snapshot) < 0 && not !stop do
    let listener = snapshot.(!index) in
    if listener.once then Event_subscription.cancel listener.subscription;
    (try listener.callback event with exception_value ->
      report handler ~kind ~scope:Global ~owner_num:None
        exception_value);
    if event.propagation_stopped then stop := true;
    index := !index + 1
  done

let emit_global_paste handler (channel : paste_event channel)
    (event : paste_event) ~stop =
  let snapshot = channel.listeners in
  let index = ref 0 in
  while Int.compare !index (Array.length snapshot) < 0 && not !stop do
    let listener = snapshot.(!index) in
    if listener.once then Event_subscription.cancel listener.subscription;
    (try listener.callback event with exception_value ->
      report handler ~kind:Paste ~scope:Global ~owner_num:None exception_value);
    if event.propagation_stopped then stop := true;
    index := !index + 1
  done

let emit_internal_key handler ~kind (listeners : internal_key_listener array)
    (event : key_event) ~stop =
  let snapshot = listeners in
  let index = ref 0 in
  while Int.compare !index (Array.length snapshot) < 0 && not !stop do
    let listener = snapshot.(!index) in
    (try listener.callback event with exception_value ->
      report handler ~kind ~scope:Renderable
        ~owner_num:(Some listener.owner_num) exception_value);
    if event.propagation_stopped then stop := true;
    index := !index + 1
  done

let emit_internal_paste handler (listeners : internal_paste_listener array)
    (event : paste_event) ~stop =
  let snapshot = listeners in
  let index = ref 0 in
  while Int.compare !index (Array.length snapshot) < 0 && not !stop do
    let listener = snapshot.(!index) in
    (try listener.callback event with exception_value ->
      report handler ~kind:Paste ~scope:Renderable
        ~owner_num:(Some listener.owner_num) exception_value);
    if event.propagation_stopped then stop := true;
    index := !index + 1
  done

let process_key_event handler (event : key_event) (channel : key_event channel)
    (internal : internal_key_listener array) =
  let stop = ref false in
  emit_global_key handler ~kind:event.kind channel event ~stop;
  if not event.default_prevented && not !stop then
    emit_internal_key handler ~kind:event.kind internal event ~stop;
  true

let process_key handler ~raw ~key ~modifiers =
  process_key_event handler
    { raw; key; modifiers; kind = Keypress; default_prevented = false;
      propagation_stopped = false }
    handler.keypress handler.internal_keypress

let process_keyrelease handler ~raw ~key ~modifiers =
  process_key_event handler
    { raw; key; modifiers; kind = Keyrelease; default_prevented = false;
      propagation_stopped = false }
    handler.keyrelease handler.internal_keyrelease

let process_paste handler raw =
  let event = { raw; default_prevented = false; propagation_stopped = false } in
  let stop = ref false in
  emit_global_paste handler handler.paste event ~stop;
  if not event.default_prevented && not !stop then
    emit_internal_paste handler handler.internal_paste event ~stop;
  true

let clear_channel channel = channel.listeners <- [||]

let clear handler =
  clear_channel handler.keypress;
  clear_channel handler.keyrelease;
  clear_channel handler.paste;
  handler.internal_keypress <- [||];
  handler.internal_keyrelease <- [||];
  handler.internal_paste <- [||]
