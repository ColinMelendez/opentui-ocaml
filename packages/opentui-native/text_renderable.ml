type t = {
  node : Layout.Node.t;
  mutable text : string;
}

let copy_text text = String.sub text 0 (String.length text)

let create ~node ~text = { node; text = copy_text text }
let text renderable = renderable.text
let set_text renderable ~text = renderable.text <- copy_text text

let invalid_coordinate = Error.Native Opentui_raw.Error.Invalid_argument

let coordinate value =
  let max_coordinate = Int32.to_float Int32.max_int in
  match classify_float value with
  | FP_nan | FP_infinite -> Error invalid_coordinate
  | FP_zero | FP_subnormal | FP_normal ->
      if Float.compare value 0.0 < 0
         || Float.compare value max_coordinate > 0
      then Error invalid_coordinate
      else Ok (Int32.of_float value)

let draw renderable frame ~foreground ~background ~attributes =
  match Layout.Node.layout renderable.node with
  | Error error -> Error error
  | Ok layout ->
      (match coordinate layout.Layout.left, coordinate layout.Layout.top with
      | Error error, _ | _, Error error -> Error error
      | Ok x, Ok y ->
          Renderer.Frame.draw_text frame ~text:renderable.text ~x ~y
            ~foreground ~background ~attributes)
