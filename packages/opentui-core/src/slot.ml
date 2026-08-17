type 'props contribution = {
  contribution_instance : Plugin_host.instance;
  contribution_render :
    'props -> (Slot_view.t option, Plugin_failure.t) result;
}

type subscriber = {
  subscriber_id : int;
  subscriber_notify : unit -> Plugin_failure.t list;
}

type 'props t = {
  slot_host : Plugin_host.t;
  slot_id : Plugin_id.t;
  slot_key : int;
  mutable slot_contributions : 'props contribution list;
  mutable next_subscriber_id : int;
  mutable subscribers : subscriber list;
}

type 'props sink = { sink_slot : 'props t }

type subscription = {
  subscription_slot : unit -> unit;
  subscription_id : int;
  mutable subscription_active : bool;
}

let id slot = slot.slot_id

let create ~host ~id =
  match Plugin_host.Private.register_slot host id with
  | Error failure -> Error failure
  | Ok slot_key ->
      let slot =
        {
          slot_host = host;
          slot_id = id;
          slot_key;
          slot_contributions = [];
          next_subscriber_id = 0;
          subscribers = [];
        }
      in
      Ok (slot, { sink_slot = slot })

let sink_host sink = sink.sink_slot.slot_host

let contribute scope sink ~render =
  let host = Plugin_host.Private.scope_host scope in
  let slot = sink.sink_slot in
  if not (host == sink_host sink) then
    Error
      (Plugin_failure.make ~slot:slot.slot_id ~phase:Plugin_failure.Install
         ~origin:Plugin_failure.Plugin ~cause:Plugin_failure.Wrong_host ())
  else
    let publish instance =
      if not (Plugin_host.Private.is_open slot.slot_host) then
        Error
          (Plugin_failure.make ~slot:slot.slot_id ~phase:Plugin_failure.Install
             ~origin:Plugin_failure.Host ~cause:Plugin_failure.Host_closed ())
      else if
        List.exists
          (fun contribution ->
            Int.equal
              (Plugin_host.Private.instance_sequence
                 contribution.contribution_instance)
              (Plugin_host.Private.instance_sequence instance))
          slot.slot_contributions
      then
        Error
          (Plugin_failure.make ~slot:slot.slot_id ~phase:Plugin_failure.Install
             ~origin:Plugin_failure.Host
             ~cause:
             (Plugin_failure.Duplicate_plugin
                (Plugin_host.Instance.id instance)) ())
      else begin
        slot.slot_contributions <-
          { contribution_instance = instance; contribution_render = render }
          :: slot.slot_contributions;
        Ok ()
      end
    in
    let withdraw instance =
      slot.slot_contributions <-
        List.filter
          (fun contribution ->
            not
              (Int.equal
                 (Plugin_host.Private.instance_sequence
                    contribution.contribution_instance)
                 (Plugin_host.Private.instance_sequence instance)))
          slot.slot_contributions;
      Ok ()
    in
    Plugin_host.Private.stage_contribution scope ~slot_id:slot.slot_id
      ~slot_key:slot.slot_key ~publish ~withdraw
      ~notify:(fun () ->
        List.fold_left
          (fun failures subscriber ->
            failures @ subscriber.subscriber_notify ())
          [] slot.subscribers)

let compare_contributions left right =
  Plugin_host.Private.compare_instances left.contribution_instance
    right.contribution_instance

let contributions slot = List.sort compare_contributions slot.slot_contributions

let subscribe slot ~notify =
  if not (Plugin_host.Private.is_open slot.slot_host) then
    Error
      (Plugin_failure.make ~slot:slot.slot_id ~phase:Plugin_failure.Create
         ~origin:Plugin_failure.Host ~cause:Plugin_failure.Host_closed ())
  else
    let subscriber_id = slot.next_subscriber_id in
    slot.next_subscriber_id <- subscriber_id + 1;
    slot.subscribers <-
      slot.subscribers @ [ { subscriber_id; subscriber_notify = notify } ];
    Ok
      {
        subscription_slot = (fun () ->
          slot.subscribers <-
            List.filter
              (fun subscriber ->
                not (Int.equal subscriber.subscriber_id subscriber_id))
              slot.subscribers);
        subscription_id = subscriber_id;
        subscription_active = true;
      }

let unsubscribe subscription =
  if subscription.subscription_active then begin
    subscription.subscription_active <- false;
    subscription.subscription_slot ()
  end

let notify slot =
  List.fold_left
    (fun failures subscriber -> failures @ subscriber.subscriber_notify ())
    [] slot.subscribers

module Private = struct
  type nonrec 'props contribution = 'props contribution
  type nonrec subscription = subscription

  let subscribe = subscribe
  let unsubscribe = unsubscribe
  let contributions = contributions
  let contribution_instance contribution = contribution.contribution_instance
  let contribution_render contribution = contribution.contribution_render
  let host slot = slot.slot_host
  let id slot = slot.slot_id
  let notify = notify
end
