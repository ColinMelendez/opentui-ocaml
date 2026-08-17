type 'target t = {
  read : 'target -> (float, Error.t) result;
  write : 'target -> float -> (unit, Error.t) result;
}

type binding = Binding : {
  property : 'target t;
  target : 'target;
  to_value : float;
}
  -> binding

let create ~read ~write = { read; write }

let bind property target ~to_ = Binding { property; target; to_value = to_ }

let bind_ref value ~to_ =
  let property =
    create
      ~read:(fun reference ->
        let current = !reference in
        if Float.is_finite current then Ok current
        else Error (Error.Invalid_number { field = "property value"; value = current }))
      ~write:(fun reference next ->
        if Float.is_finite next then begin
          reference := next;
          Ok ()
        end else
          Error (Error.Invalid_number { field = "property value"; value = next }))
  in
  bind property value ~to_

let validate binding =
  match binding with
  | Binding { to_value; _ } when Float.is_finite to_value -> Ok ()
  | Binding { to_value; _ } ->
      Error (Error.Invalid_number { field = "binding endpoint"; value = to_value })

let read binding =
  match binding with
  | Binding { property; target; _ } -> property.read target

let target_value binding =
  match binding with
  | Binding { to_value; _ } -> to_value

let write binding value =
  match binding with
  | Binding { property; target; _ } -> property.write target value

module Private = struct
  let validate = validate
  let target_value = target_value
  let read = read
  let write = write
end
