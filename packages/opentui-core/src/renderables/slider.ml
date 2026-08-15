type orientation = Horizontal | Vertical

type t = {
  renderable : Renderable.t;
  orientation : orientation;
  mutable value : float;
  mutable minimum : float;
  mutable maximum : float;
  mutable viewport_size : float;
  mutable background_color : Color.t;
  mutable foreground_color : Color.t;
  mutable drag_offset_virtual : int option;
  change_events : float Event_kernel.t;
}

let default_track_color =
  match Color.rgba ~red:37 ~green:37 ~blue:39 ~alpha:255 with
  | Ok color -> color
  | Error _ -> Color.black

let default_thumb_color =
  match Color.rgba ~red:154 ~green:158 ~blue:163 ~alpha:255 with
  | Ok color -> color
  | Error _ -> Color.white

let clamp value minimum maximum = Float.max minimum (Float.min maximum value)
let range slider = Float.max 0.0 (slider.maximum -. slider.minimum)
let effective_viewport slider = Float.max 1.0 slider.viewport_size

let thumb_geometry slider length =
  let available = max 0 (length * 2) in
  let span = range slider in
  if Int.equal available 0 then 0, 0
  else if Float.equal span 0.0 then 0, available
  else
    let ratio =
      effective_viewport slider /. (span +. effective_viewport slider)
    in
    let size =
      max 1
        (min available
           (int_of_float (Float.floor (float_of_int available *. ratio))))
    in
    let position_ratio = (slider.value -. slider.minimum) /. span in
    let start =
      int_of_float
        (Float.round
           (position_ratio *. float_of_int (available - size)))
    in
    max 0 (min (available - size) start), size

let set_cell buffer ~x ~y ~character ~foreground ~background =
  Buffer.set_cell buffer ~x:(Int32.of_int x) ~y:(Int32.of_int y)
    ~character:(Int32.of_int character) ~foreground ~background ~attributes:0l

let render_self slider renderable buffer delta_time =
  ignore delta_time;
  let width = max 0 (int_of_float (Renderable.width renderable)) in
  let height = max 0 (int_of_float (Renderable.height renderable)) in
  let length =
    match slider.orientation with Horizontal -> width | Vertical -> height
  in
  let thumb_start, thumb_size = thumb_geometry slider length in
  let result = ref (Ok ()) in
  let draw_cell x y character foreground =
    match !result with
    | Error _ -> ()
    | Ok () ->
        result :=
          set_cell buffer ~x ~y ~character ~foreground
            ~background:slider.background_color
  in
  for y = 0 to height - 1 do
    for x = 0 to width - 1 do
      draw_cell x y (Char.code ' ') slider.background_color
    done
  done;
  (match slider.orientation with
  | Horizontal ->
      for x = 0 to width - 1 do
        let cell_start = x * 2 in
        let cell_end = cell_start + 2 in
        let covered_start = max thumb_start cell_start in
        let covered_end = min (thumb_start + thumb_size) cell_end in
        let coverage = covered_end - covered_start in
        if coverage > 0 then begin
          let character =
            if coverage >= 2 then 0x2588
            else if Int.equal covered_start cell_start then 0x258c
            else 0x2590
          in
          for y = 0 to height - 1 do
            draw_cell x y character slider.foreground_color
          done
        end
      done
  | Vertical ->
      for y = 0 to height - 1 do
        let cell_start = y * 2 in
        let cell_end = cell_start + 2 in
        let covered_start = max thumb_start cell_start in
        let covered_end = min (thumb_start + thumb_size) cell_end in
        let coverage = covered_end - covered_start in
        if coverage > 0 then begin
          let character =
            if coverage >= 2 then 0x2588
            else if Int.equal covered_start cell_start then 0x2580
            else 0x2584
          in
          for x = 0 to width - 1 do
            draw_cell x y character slider.foreground_color
          done
        end
      done);
  !result

let ensure_alive slider =
  if Renderable.is_destroyed slider.renderable then Error Error.Destroyed
  else Ok ()

let emit_change slider =
  ignore (Event_kernel.emit slider.change_events slider.value);
  ignore (Renderable.request_render slider.renderable)

let set_value slider value =
  Result.bind (ensure_alive slider) (fun () ->
      let next = clamp value slider.minimum slider.maximum in
      if not (Float.equal next slider.value) then begin
        slider.value <- next;
        emit_change slider
      end;
      Ok ())

let set_min slider value =
  Result.bind (ensure_alive slider) (fun () ->
      slider.minimum <- Float.min value slider.maximum;
      let next = clamp slider.value slider.minimum slider.maximum in
      if not (Float.equal next slider.value) then begin
        slider.value <- next;
        emit_change slider
      end
      else ignore (Renderable.request_render slider.renderable);
      Ok ())

let set_max slider value =
  Result.bind (ensure_alive slider) (fun () ->
      slider.maximum <- Float.max value slider.minimum;
      let next = clamp slider.value slider.minimum slider.maximum in
      if not (Float.equal next slider.value) then begin
        slider.value <- next;
        emit_change slider
      end
      else ignore (Renderable.request_render slider.renderable);
      Ok ())

let set_viewport_size slider value =
  Result.bind (ensure_alive slider) (fun () ->
      slider.viewport_size <-
        Float.max 0.01 (Float.min value (range slider));
      ignore (Renderable.request_render slider.renderable);
      Ok ())

let relative_position slider event =
  let coordinate =
    match slider.orientation with
    | Horizontal ->
        float_of_int (Renderable.mouse_x event)
        -. Renderable.screen_x slider.renderable
    | Vertical ->
        float_of_int (Renderable.mouse_y event)
        -. Renderable.screen_y slider.renderable
  in
  let length =
    match slider.orientation with
    | Horizontal -> Renderable.width slider.renderable
    | Vertical -> Renderable.height slider.renderable
  in
  let ratio =
    if Float.compare length 0.0 <= 0 then 0.0
    else Float.max 0.0 (Float.min 1.0 (coordinate /. length))
  in
  slider.minimum +. (range slider *. ratio)

let virtual_mouse_position slider event =
  let coordinate =
    match slider.orientation with
    | Horizontal ->
        float_of_int (Renderable.mouse_x event)
        -. Renderable.screen_x slider.renderable
    | Vertical ->
        float_of_int (Renderable.mouse_y event)
        -. Renderable.screen_y slider.renderable
  in
  let length =
    match slider.orientation with
    | Horizontal -> Renderable.width slider.renderable
    | Vertical -> Renderable.height slider.renderable
  in
  let clamped = Float.max 0.0 (Float.min length coordinate) in
  int_of_float (Float.round (clamped *. 2.0))

let update_value_from_mouse slider event ~offset_virtual =
  let length =
    match slider.orientation with
    | Horizontal -> int_of_float (Float.floor (Renderable.width slider.renderable))
    | Vertical -> int_of_float (Float.floor (Renderable.height slider.renderable))
  in
  let virtual_track = max 0 (length * 2) in
  let _, thumb_size = thumb_geometry slider length in
  let max_start = max 0 (virtual_track - thumb_size) in
  let desired_start =
    max 0
      (min max_start
         (virtual_mouse_position slider event - offset_virtual))
  in
  let ratio =
    if Int.equal max_start 0 then 0.0
    else float_of_int desired_start /. float_of_int max_start
  in
  ignore (set_value slider (slider.minimum +. (range slider *. ratio)))

let handle_mouse slider event =
  match Renderable.mouse_kind event with
  | Renderable.Down ->
      Renderable.mouse_prevent_default event;
      Renderable.mouse_stop_propagation event;
      let length =
        match slider.orientation with
        | Horizontal -> int_of_float (Float.floor (Renderable.width slider.renderable))
        | Vertical -> int_of_float (Float.floor (Renderable.height slider.renderable))
      in
      let thumb_start, thumb_size = thumb_geometry slider length in
      let mouse = virtual_mouse_position slider event in
      if mouse >= thumb_start && mouse < thumb_start + thumb_size then
        slider.drag_offset_virtual <- Some (mouse - thumb_start)
      else begin
        ignore (set_value slider (relative_position slider event));
        let new_start, new_size = thumb_geometry slider length in
        let offset = max 0 (min new_size (mouse - new_start)) in
        slider.drag_offset_virtual <- Some offset
      end
  | Renderable.Drag ->
      Renderable.mouse_prevent_default event;
      Renderable.mouse_stop_propagation event;
      (match slider.drag_offset_virtual with
      | None -> ignore (set_value slider (relative_position slider event))
      | Some offset -> update_value_from_mouse slider event ~offset_virtual:offset)
  | Renderable.Up | Renderable.Drag_end ->
      (match slider.drag_offset_virtual with
      | None -> ()
      | Some offset -> update_value_from_mouse slider event ~offset_virtual:offset);
      slider.drag_offset_virtual <- None
  | Renderable.Move | Renderable.Drop | Renderable.Over | Renderable.Out
  | Renderable.Scroll -> ()

let handle_key_press slider event =
  let amount =
    let span = range slider in
    if Float.equal span 0.0 then 0.0 else span /. 5.0
  in
  let named = Lib.Key_handler.key event in
  let delta =
    match slider.orientation, named with
    | Horizontal, Lib.Key_decoder.Named Left -> Some (-.amount)
    | Horizontal, Lib.Key_decoder.Named Right -> Some amount
    | Vertical, Lib.Key_decoder.Named Up -> Some (-.amount)
    | Vertical, Lib.Key_decoder.Named Down -> Some amount
    | _, Lib.Key_decoder.Named Page_up -> Some (-.(range slider /. 2.0))
    | _, Lib.Key_decoder.Named Page_down -> Some (range slider /. 2.0)
    | _, Lib.Key_decoder.Named Home -> Some (-.(range slider))
    | _, Lib.Key_decoder.Named End -> Some (range slider)
    | _ -> None
  in
  match delta with
  | None -> false
  | Some delta ->
      Lib.Key_handler.prevent_default event;
      ignore (set_value slider (slider.value +. delta));
      true

let create context ~orientation ?id ?(value = 0.0) ?(min = 0.0) ?(max = 100.0)
    ?viewport_size ?(background_color = default_track_color)
    ?(foreground_color = default_thumb_color) ?(focusable = false) ?width ?height
    () =
  if Float.compare max min < 0 then Error Error.Invalid_argument
  else
    match Renderable.Private.create context ?id () with
    | Error error -> Error error
    | Ok renderable ->
        let slider =
          {
            renderable;
            orientation;
            value = clamp value min max;
            minimum = min;
            maximum = max;
            viewport_size =
              Float.max 0.01
                (Float.min
                   (Option.value viewport_size
                      ~default:(Float.max 1.0 ((max -. min) *. 0.1)))
                   (Float.max 0.0 (max -. min)));
            background_color;
            foreground_color;
            drag_offset_virtual = None;
            change_events = Event_kernel.create ();
          }
        in
        let behavior =
          Renderable.Private.make_behavior
            ~render_self:(render_self slider)
            ~key_press:(fun _ event -> ignore (handle_key_press slider event))
            ~mouse_event:(fun _ event -> handle_mouse slider event)
            ~destroy_self:(fun _ -> Event_kernel.clear slider.change_events)
            ()
        in
        Renderable.Private.set_behavior renderable behavior;
        let configure result operation =
          match result with Error error -> Error error | Ok () -> operation ()
        in
        let result =
          configure (Renderable.set_focusable renderable focusable) (fun () ->
              match width with
              | None -> Ok ()
              | Some width -> Renderable.set_width renderable width)
        in
        let result =
          configure result (fun () ->
              match height with
              | None -> Ok ()
              | Some height -> Renderable.set_height renderable height)
        in
        (match result with
        | Ok () -> Ok slider
        | Error error ->
            Renderable.destroy renderable;
            Error error)

let as_renderable slider = slider.renderable
let orientation slider = slider.orientation
let value slider = slider.value
let min slider = slider.minimum
let max slider = slider.maximum
let viewport_size slider = slider.viewport_size
let background_color slider = slider.background_color
let foreground_color slider = slider.foreground_color

let set_background_color slider color =
  Result.bind (ensure_alive slider) (fun () ->
      slider.background_color <- color;
      Renderable.request_render slider.renderable)

let set_foreground_color slider color =
  Result.bind (ensure_alive slider) (fun () ->
      slider.foreground_color <- color;
      Renderable.request_render slider.renderable)

let on_change slider callback = Event_kernel.on slider.change_events callback
let handle_key_press = handle_key_press
let destroy slider = Renderable.destroy slider.renderable
