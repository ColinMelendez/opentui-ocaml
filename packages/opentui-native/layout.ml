type direction = Inherit | Ltr | Rtl

type layout = {
  left : float;
  top : float;
  right : float;
  bottom : float;
  width : float;
  height : float;
}

type t = {
  yoga : Opentui_raw.Yoga.t;
  mutable closed : bool;
  mutable root : node option;
}

and node = {
  owner : t;
  raw : Opentui_raw.Yoga.Node.t;
}

module Node = struct
  type t = node

  (* Keep the preflight rule aligned with the raw C facade's float32 bound. *)
  let max_dimension = 3.4028234663852886e38

  let ensure_open node =
    if node.owner.closed then Error Error.Closed else Ok ()

  let map_native result =
    match result with
    | Ok value -> Ok value
    | Error error -> Error (Error.Native error)

  let valid_dimension value =
    match classify_float value with
    | FP_nan | FP_infinite -> false
    | FP_zero | FP_subnormal | FP_normal ->
        Float.compare value 0.0 >= 0
        && Float.compare value max_dimension <= 0

  let set_dimensions node ~width ~height =
    match ensure_open node with
    | Error error -> Error error
    | Ok () when not (valid_dimension width && valid_dimension height) ->
        Error (Error.Native Opentui_raw.Error.Invalid_argument)
    | Ok () ->
        (match Opentui_raw.Yoga.Node.set_width node.raw width with
        | Error error -> Error (Error.Native error)
        | Ok () -> map_native (Opentui_raw.Yoga.Node.set_height node.raw height))

  let layout node =
    match ensure_open node with
    | Error error -> Error error
    | Ok () ->
        (match Opentui_raw.Yoga.Node.layout node.raw with
        | Error error -> Error (Error.Native error)
        | Ok layout ->
            Ok
              {
                left = layout.Opentui_raw.Yoga.left;
                top = layout.Opentui_raw.Yoga.top;
                right = layout.Opentui_raw.Yoga.right;
                bottom = layout.Opentui_raw.Yoga.bottom;
                width = layout.Opentui_raw.Yoga.width;
                height = layout.Opentui_raw.Yoga.height;
              })
end

let error_of_native error = Error.Native error

let map_native result =
  match result with
  | Ok value -> Ok value
  | Error error -> Error (Error.Native error)

let create () =
  match Opentui_raw.Yoga.create () with
  | Error error -> Error (error_of_native error)
  | Ok yoga ->
      let owner = { yoga; closed = false; root = None } in
      (match Opentui_raw.Yoga.root yoga with
      | Error error ->
          Opentui_raw.Yoga.close yoga;
          Error (error_of_native error)
      | Ok raw ->
          let root = { owner; raw } in
          owner.root <- Some root;
          Ok owner)

let close layout =
  if not layout.closed then (
    layout.closed <- true;
    Opentui_raw.Yoga.close layout.yoga)

let root layout =
  if layout.closed then Error Error.Closed
  else
    match layout.root with
    | Some root -> Ok root
    | None -> Error Error.Closed

let add_child ~parent =
  if parent.owner.closed then Error Error.Closed
  else
    match Opentui_raw.Yoga.add_child parent.owner.yoga ~parent:parent.raw with
    | Error error -> Error (error_of_native error)
    | Ok raw -> Ok { owner = parent.owner; raw }

let remove_child ~parent ~child =
  if parent.owner.closed || child.owner.closed then Error Error.Closed
  else if not (parent.owner == child.owner) then
    Error (Error.Native Opentui_raw.Error.Invalid_argument)
  else
    map_native
      (Opentui_raw.Yoga.remove_child parent.owner.yoga
         ~parent:parent.raw ~child:child.raw)

let move_child ~parent ~child ~index =
  if parent.owner.closed || child.owner.closed then Error Error.Closed
  else if not (parent.owner == child.owner) then
    Error (Error.Native Opentui_raw.Error.Invalid_argument)
  else if Int32.compare index 0l < 0 then
    Error (Error.Native Opentui_raw.Error.Invalid_argument)
  else
    map_native
      (Opentui_raw.Yoga.move_child parent.owner.yoga
         ~parent:parent.raw ~child:child.raw ~index)

let direction_code direction =
  match direction with
  | Inherit -> Opentui_raw.Yoga.Inherit
  | Ltr -> Opentui_raw.Yoga.Ltr
  | Rtl -> Opentui_raw.Yoga.Rtl

let valid_dimensions width height =
  Node.valid_dimension width && Node.valid_dimension height

let calculate layout ~width ~height ~direction =
  if layout.closed then Error Error.Closed
  else if not (valid_dimensions width height) then
    Error (Error.Native Opentui_raw.Error.Invalid_argument)
  else
    map_native
      (Opentui_raw.Yoga.calculate layout.yoga ~width ~height
         ~direction:(direction_code direction))
