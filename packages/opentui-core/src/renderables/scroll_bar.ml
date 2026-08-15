type orientation = Horizontal | Vertical
type scroll_unit = Absolute | Viewport | Content | Step

type arrow = {
  renderable : Renderable.t;
  direction : orientation * bool;
  mutable foreground_color : Color.t;
  mutable background_color : Color.t;
}

type t = {
  renderable : Renderable.t;
  slider : Slider.t;
  start_arrow : arrow;
  end_arrow : arrow;
  orientation : orientation;
  mutable scroll_size : float;
  mutable scroll_position : float;
  mutable viewport_size : float;
  mutable scroll_step : float option;
  mutable show_arrows : bool;
  mutable manual_visibility : bool;
  change_events : float Event_kernel.t;
  mutable destroyed : bool;
}

let slider_orientation = function Horizontal -> Slider.Horizontal | Vertical -> Slider.Vertical

let default_track_background_color =
  match Color.rgba ~red:37 ~green:37 ~blue:39 ~alpha:255 with
  | Ok color -> color
  | Error _ -> Color.black

let default_track_foreground_color =
  match Color.rgba ~red:154 ~green:158 ~blue:163 ~alpha:255 with
  | Ok color -> color
  | Error _ -> Color.white

let arrow_code (orientation, ending) =
  match orientation, ending with
  | Vertical, false -> 0x25b2
  | Vertical, true -> 0x25bc
  | Horizontal, false -> 0x25c0
  | Horizontal, true -> 0x25b6

let render_arrow arrow renderable buffer _delta_time =
  Buffer.set_cell buffer
    ~x:(Int32.of_float (Renderable.screen_x renderable))
    ~y:(Int32.of_float (Renderable.screen_y renderable))
    ~character:(Int32.of_int (arrow_code arrow.direction))
    ~foreground:arrow.foreground_color ~background:arrow.background_color
    ~attributes:0l

let make_arrow context ~orientation ~ending ~foreground_color ~background_color
    ?id () =
  match Renderable.Private.create context ?id () with
  | Error error -> Error error
  | Ok renderable ->
      let arrow =
        { renderable; direction = orientation, ending; foreground_color; background_color }
      in
      let behavior =
        Renderable.Private.make_behavior
          ~render_self:(render_arrow arrow)
          ()
      in
      Renderable.Private.set_behavior renderable behavior;
      let result = Renderable.set_width renderable (Yoga.Point 1.0) in
      let result =
        Result.bind result (fun () ->
            Renderable.set_height renderable (Yoga.Point 1.0))
      in
      match result with
      | Ok () -> Ok arrow
      | Error error ->
          Renderable.destroy renderable;
          Error error

let ensure_alive bar =
  if bar.destroyed || Renderable.is_destroyed bar.renderable then Error Error.Destroyed
  else Ok ()

let maximum_position bar = Float.max 0.0 (bar.scroll_size -. bar.viewport_size)

let rounded_position bar value =
  let clamped = Float.max 0.0 (Float.min (maximum_position bar) value) in
  Float.round clamped

let emit_change bar =
  ignore (Event_kernel.emit bar.change_events bar.scroll_position);
  ignore (Renderable.request_render bar.renderable)

let update_slider bar =
  ignore (Slider.set_min bar.slider 0.0);
  ignore (Slider.set_max bar.slider (maximum_position bar));
  ignore (Slider.set_viewport_size bar.slider (max 0.01 bar.viewport_size));
  ignore (Slider.set_value bar.slider bar.scroll_position)

let recalculate_visibility bar =
  if not bar.manual_visibility then
    let should_show = Float.compare bar.scroll_size bar.viewport_size > 0 in
    ignore (Renderable.set_visible bar.renderable should_show)

let set_scroll_position bar value =
  Result.bind (ensure_alive bar) (fun () ->
      let next = rounded_position bar value in
      if not (Float.equal next bar.scroll_position) then begin
        bar.scroll_position <- next;
        update_slider bar;
        emit_change bar
      end;
      Ok ())

let set_scroll_size bar value =
  Result.bind (ensure_alive bar) (fun () ->
      if Float.compare value 0.0 < 0 then Error Error.Invalid_argument
      else begin
        bar.scroll_size <- value;
        let previous = bar.scroll_position in
        bar.scroll_position <- rounded_position bar previous;
        recalculate_visibility bar;
        update_slider bar;
        if not (Float.equal previous bar.scroll_position) then emit_change bar;
        ignore (Renderable.request_render bar.renderable);
        Ok ()
      end)

let set_viewport_size bar value =
  Result.bind (ensure_alive bar) (fun () ->
      if Float.compare value 0.0 < 0 then Error Error.Invalid_argument
      else begin
        bar.viewport_size <- Float.max 1.0 value;
        let previous = bar.scroll_position in
        bar.scroll_position <- rounded_position bar previous;
        recalculate_visibility bar;
        update_slider bar;
        if not (Float.equal previous bar.scroll_position) then emit_change bar;
        ignore (Renderable.request_render bar.renderable);
        Ok ()
      end)

let set_show_arrows bar value =
  Result.bind (ensure_alive bar) (fun () ->
      bar.show_arrows <- value;
      ignore (Renderable.set_visible bar.start_arrow.renderable value);
      ignore (Renderable.set_visible bar.end_arrow.renderable value);
      Ok ())

let set_manual_visibility bar value =
  bar.manual_visibility <- value

let scroll_by bar delta unit =
  let multiplier =
    match unit with
    | Absolute -> 1.0
    | Viewport -> bar.viewport_size
    | Content -> bar.scroll_size
    | Step -> Option.value bar.scroll_step ~default:1.0
  in
  set_scroll_position bar (bar.scroll_position +. (delta *. multiplier))

let arrow_mouse_handler bar ~ending event =
  match Renderable.mouse_kind event with
  | Renderable.Down ->
      Renderable.mouse_prevent_default event;
      Renderable.mouse_stop_propagation event;
      ignore (scroll_by bar (if ending then 0.5 else -.0.5) Viewport)
  | Renderable.Up | Renderable.Drag_end ->
      Renderable.mouse_stop_propagation event
  | Renderable.Move | Renderable.Drag | Renderable.Drop | Renderable.Over
  | Renderable.Out | Renderable.Scroll -> ()

let handle_key_press bar event =
  let horizontal =
    match bar.orientation with Horizontal -> true | Vertical -> false
  in
  let direction = Lib.Key_handler.key event in
  let change =
    match direction with
    | Lib.Key_decoder.Named Lib.Key_decoder.Left when horizontal -> Some (-0.2, Viewport)
    | Lib.Key_decoder.Named Lib.Key_decoder.Right when horizontal -> Some (0.2, Viewport)
    | Lib.Key_decoder.Named Lib.Key_decoder.Up when not horizontal -> Some (-0.2, Viewport)
    | Lib.Key_decoder.Named Lib.Key_decoder.Down when not horizontal -> Some (0.2, Viewport)
    | Lib.Key_decoder.Named Lib.Key_decoder.Page_up -> Some (-0.5, Viewport)
    | Lib.Key_decoder.Named Lib.Key_decoder.Page_down -> Some (0.5, Viewport)
    | Lib.Key_decoder.Named Lib.Key_decoder.Home -> Some (-1.0, Content)
    | Lib.Key_decoder.Named Lib.Key_decoder.End -> Some (1.0, Content)
    | Lib.Key_decoder.Character bytes when Bytes.equal bytes (Bytes.of_string "h") && horizontal -> Some (-0.2, Viewport)
    | Lib.Key_decoder.Character bytes when Bytes.equal bytes (Bytes.of_string "l") && horizontal -> Some (0.2, Viewport)
    | Lib.Key_decoder.Character bytes when Bytes.equal bytes (Bytes.of_string "k") && not horizontal -> Some (-0.2, Viewport)
    | Lib.Key_decoder.Character bytes when Bytes.equal bytes (Bytes.of_string "j") && not horizontal -> Some (0.2, Viewport)
    | _ -> None
  in
  match change with
  | None -> false
  | Some (delta, unit) ->
      Lib.Key_handler.prevent_default event;
      ignore (scroll_by bar delta unit);
      true

let create context ~orientation ?id ?(show_arrows = false)
    ?(track_background_color = default_track_background_color)
    ?(track_foreground_color = default_track_foreground_color)
    ?(arrow_foreground_color = Color.white)
    ?(arrow_background_color = Color.transparent) ?width ?height () =
  match Renderable.Private.create context ?id () with
  | Error error -> Error error
  | Ok renderable ->
      let cleanup () = Renderable.destroy renderable in
      let slider_result =
        Slider.create context ~orientation:(slider_orientation orientation)
          ~min:0.0 ~max:0.0 ~viewport_size:1.0
          ~background_color:track_background_color
          ~foreground_color:track_foreground_color ~focusable:false ()
      in
      (match slider_result with
      | Error error -> cleanup (); Error error
      | Ok slider ->
          (match
             make_arrow context ~orientation ~ending:false
               ~foreground_color:arrow_foreground_color
               ~background_color:arrow_background_color ()
           with
          | Error error -> Slider.destroy slider; cleanup (); Error error
          | Ok start_arrow ->
              (match
                 make_arrow context ~orientation ~ending:true
                   ~foreground_color:arrow_foreground_color
                   ~background_color:arrow_background_color ()
               with
              | Error error ->
                  Renderable.destroy start_arrow.renderable;
                  Slider.destroy slider;
                  cleanup ();
                  Error error
              | Ok end_arrow ->
                  let bar =
                    {
                      renderable;
                      slider;
                      start_arrow;
                      end_arrow;
                      orientation;
                      scroll_size = 0.0;
                      scroll_position = 0.0;
                      viewport_size = 0.0;
                      scroll_step = None;
                      show_arrows;
                      manual_visibility = false;
                      change_events = Event_kernel.create ();
                      destroyed = false;
                    }
                  in
                  let behavior =
                    Renderable.Private.make_behavior
                      ~key_press:(fun _ event -> ignore (handle_key_press bar event))
                      ~destroy_self:(fun _ ->
                        Event_kernel.clear bar.change_events;
                        Slider.destroy bar.slider;
                        Renderable.destroy bar.start_arrow.renderable;
                        Renderable.destroy bar.end_arrow.renderable)
                      ()
                  in
                  Renderable.Private.set_behavior renderable behavior;
                  let focus_result = Renderable.set_focusable renderable true in
                  ignore (Renderable.set_flex_direction renderable
                            (match orientation with Horizontal -> Yoga.Flex_row | Vertical -> Yoga.Flex_column));
                  ignore (Renderable.set_align_items renderable Yoga.Align_stretch);
                  let slider_renderable = Slider.as_renderable slider in
                  ignore (Renderable.set_flex_grow slider_renderable (Some 1.0));
                  ignore (Renderable.set_flex_shrink slider_renderable (Some 1.0));
                  (match orientation with
                  | Vertical ->
                      ignore
                        (Renderable.set_width slider_renderable
                           (Yoga.Point 1.0));
                      ignore
                        (Renderable.set_height slider_renderable
                           (Yoga.Percent 100.0))
                  | Horizontal ->
                      ignore
                        (Renderable.set_width slider_renderable
                           (Yoga.Percent 100.0));
                      ignore
                        (Renderable.set_height slider_renderable
                           (Yoga.Point 1.0)));
                  ignore (Renderable.set_visible start_arrow.renderable show_arrows);
                  ignore (Renderable.set_visible end_arrow.renderable show_arrows);
                  ignore (Renderable.set_on_mouse_down start_arrow.renderable
                            (Some (arrow_mouse_handler bar ~ending:false)));
                  ignore (Renderable.set_on_mouse_up start_arrow.renderable
                            (Some (arrow_mouse_handler bar ~ending:false)));
                  ignore (Renderable.set_on_mouse_down end_arrow.renderable
                            (Some (arrow_mouse_handler bar ~ending:true)));
                  ignore (Renderable.set_on_mouse_up end_arrow.renderable
                            (Some (arrow_mouse_handler bar ~ending:true)));
                  let attach child index =
                    Renderable.Private.attach ~parent:renderable ~child ~index
                  in
                  let result = Result.bind focus_result (fun () -> attach start_arrow.renderable 0) in
                  let result = Result.bind result (fun _ -> attach slider_renderable 1) in
                  let result = Result.bind result (fun _ -> attach end_arrow.renderable 2) in
                  let result = Result.bind result (fun _ ->
                      match width with None -> Ok () | Some value -> Renderable.set_width renderable value) in
                  let result = Result.bind result (fun () ->
                      match height with None -> Ok () | Some value -> Renderable.set_height renderable value) in
                  (match result with
                  | Error error -> Renderable.destroy_recursively renderable; Error error
                  | Ok () ->
                      let slider_subscription =
                        Slider.on_change slider (fun value ->
                            if not (Float.equal value bar.scroll_position) then begin
                              bar.scroll_position <- Float.round value;
                              ignore
                                (Event_kernel.emit bar.change_events
                                   bar.scroll_position);
                              ignore (Renderable.request_render bar.renderable)
                            end)
                      in
                      ignore slider_subscription;
                      Ok bar))))

let as_renderable bar = bar.renderable
let slider bar = bar.slider
let orientation bar = bar.orientation
let start_arrow bar = bar.start_arrow.renderable
let end_arrow bar = bar.end_arrow.renderable
let track_background_color bar = Slider.background_color bar.slider
let track_foreground_color bar = Slider.foreground_color bar.slider

let set_track_background_color bar color =
  Result.bind (ensure_alive bar) (fun () ->
      Slider.set_background_color bar.slider color)

let set_track_foreground_color bar color =
  Result.bind (ensure_alive bar) (fun () ->
      Slider.set_foreground_color bar.slider color)

let arrow_foreground_color bar = bar.start_arrow.foreground_color
let arrow_background_color bar = bar.start_arrow.background_color

let set_arrow_foreground_color bar color =
  Result.bind (ensure_alive bar) (fun () ->
      bar.start_arrow.foreground_color <- color;
      bar.end_arrow.foreground_color <- color;
      ignore (Renderable.request_render bar.renderable);
      Ok ())

let set_arrow_background_color bar color =
  Result.bind (ensure_alive bar) (fun () ->
      bar.start_arrow.background_color <- color;
      bar.end_arrow.background_color <- color;
      ignore (Renderable.request_render bar.renderable);
      Ok ())
let visible bar = Renderable.visible bar.renderable

let set_visible bar value =
  Result.bind (ensure_alive bar) (fun () ->
      set_manual_visibility bar true;
      Renderable.set_visible bar.renderable value)

let reset_visibility_control bar =
  set_manual_visibility bar false;
  recalculate_visibility bar

let show_arrows bar = bar.show_arrows
let scroll_size bar = bar.scroll_size
let scroll_position bar = bar.scroll_position
let viewport_size bar = bar.viewport_size
let scroll_step bar = bar.scroll_step
let set_scroll_size = set_scroll_size
let set_scroll_position = set_scroll_position
let set_viewport_size = set_viewport_size

let set_scroll_step bar value =
  Result.bind (ensure_alive bar) (fun () ->
      match value with
      | Some value when Float.compare value 0.0 < 0 -> Error Error.Invalid_argument
      | _ ->
          bar.scroll_step <- value;
          Ok ())

let on_change bar callback = Event_kernel.on bar.change_events callback

let destroy bar =
  if not bar.destroyed then begin
    bar.destroyed <- true;
    Renderable.destroy_recursively bar.renderable
  end
