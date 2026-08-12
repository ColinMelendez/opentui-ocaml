type t = {
  node : Yoga.Node.t;
  mutable text : string;
}

let copy_text text = String.sub text 0 (String.length text)

let create ~node ~text = { node; text = copy_text text }
let text renderable = renderable.text
let set_text renderable ~text = renderable.text <- copy_text text

let invalid_coordinate = Native.Error.Native Opentui_raw.Error.Invalid_argument

let coordinate value =
  let max_coordinate = Int32.to_float Int32.max_int in
  match classify_float value with
  | FP_nan | FP_infinite -> Error invalid_coordinate
  | FP_zero | FP_subnormal | FP_normal ->
      if Float.compare value 0.0 < 0
         || Float.compare value max_coordinate > 0
      then Error invalid_coordinate
      else Ok (Int32.of_float value)

let draw renderable frame ~offset_x ~offset_y ~foreground ~background
    ~attributes =
  match Yoga.Node.layout renderable.node with
  | Error error -> Error error
  | Ok layout ->
      (match
             coordinate (layout.Yoga.left +. offset_x),
             coordinate (layout.Yoga.top +. offset_y)
       with
      | Error error, _ | _, Error error -> Error error
      | Ok x, Ok y ->
          Renderer.Frame.draw_text frame ~text:renderable.text ~x ~y
            ~foreground ~background ~attributes)
