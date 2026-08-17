type state = Fresh | Claimed | Active | Inactive | Rejected | Destroyed

type t = {
  view_renderable : Renderable.t;
  on_activate : (unit -> (unit, Plugin_failure.t) result) option;
  on_deactivate : (unit -> (unit, Plugin_failure.t) result) option;
  mutable state : state;
}

let create ?on_activate ?on_deactivate view_renderable =
  { view_renderable; on_activate; on_deactivate; state = Fresh }

let renderable view = view.view_renderable

let claim view =
  match view.state with
  | Fresh ->
      view.state <- Claimed;
      Ok ()
  | Claimed | Active | Inactive | Rejected | Destroyed ->
      Error
        (Plugin_failure.make ~phase:Plugin_failure.Create
           ~origin:Plugin_failure.Host
           ~cause:
             (Plugin_failure.Invalid_view
                Plugin_failure.View_already_claimed)
           ())

let activate view =
  match view.state with
  | Claimed ->
      begin
        match view.on_activate with
      | None ->
          view.state <- Active;
          Ok ()
      | Some callback ->
          (try
             match callback () with
             | Ok () ->
                 view.state <- Active;
                 Ok ()
             | Error failure ->
                 view.state <- Rejected;
                 Error failure
           with
          | exception_value ->
              view.state <- Rejected;
              Error
                (Plugin_failure.callback_exception ~phase:Plugin_failure.Activate
                   ~origin:Plugin_failure.Plugin exception_value ()))
      end
  | Fresh | Active | Inactive | Rejected | Destroyed ->
      Error
        (Plugin_failure.make ~phase:Plugin_failure.Activate
           ~origin:Plugin_failure.Host
           ~cause:
             (Plugin_failure.Invalid_view
                Plugin_failure.View_already_claimed)
           ())

let deactivate view =
  match view.state with
  | Active ->
      view.state <- Inactive;
      begin
        match view.on_deactivate with
      | None -> Ok ()
      | Some callback ->
          (try callback () with
          | exception_value ->
              Error
                (Plugin_failure.callback_exception
                   ~phase:Plugin_failure.Deactivate
                   ~origin:Plugin_failure.Plugin exception_value ()))
      end
  | Fresh | Claimed | Inactive | Rejected | Destroyed -> Ok ()

let destroy view = view.state <- Destroyed

let is_active view = match view.state with Active -> true | _ -> false
let is_destroyed view = match view.state with Destroyed -> true | _ -> false

module Private = struct
  let claim = claim
  let activate = activate
  let deactivate = deactivate
  let destroy = destroy
  let is_active = is_active
  let is_destroyed = is_destroyed
end
