type t = {
  mutable cancelled : bool;
  cancel_action : unit -> unit;
}

let cancel subscription =
  if not subscription.cancelled then begin
    subscription.cancelled <- true;
    subscription.cancel_action ()
  end

module Private = struct
  let create cancel_action = { cancelled = false; cancel_action }
end
