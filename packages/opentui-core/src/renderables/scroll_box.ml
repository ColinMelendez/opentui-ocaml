type sticky_start = Bottom | Top | Left | Right

type t = {
  renderable : Renderable.t;
  wrapper : Renderable.t;
  viewport : Renderable.t;
  content : Renderable.t;
  children : Layout_children.t;
  vertical_scrollbar : Scroll_bar.t;
  horizontal_scrollbar : Scroll_bar.t;
  scroll_x : bool;
  scroll_y : bool;
  acceleration : Lib.Scroll_acceleration.t;
  mutable sticky_scroll : bool;
  mutable sticky_start : sticky_start option;
  mutable viewport_culling : bool;
  mutable content_width : float;
  mutable content_height : float;
  mutable manual_content_size : bool;
  mutable scroll_accumulator_x : float;
  mutable scroll_accumulator_y : float;
  mutable auto_scroll_pointer : (int * int) option;
  mutable auto_scroll_speed : float;
  mutable auto_scroll_active : bool;
  mutable auto_scroll_accumulator_x : float;
  mutable auto_scroll_accumulator_y : float;
  mutable auto_scroll_live_acquired : bool;
  mutable selection_dragging : bool;
  mutable selection_subscription : Event_subscription.t option;
  mutable destroyed : bool;
}

let ensure_alive box =
  if box.destroyed || Renderable.is_destroyed box.renderable then Error Error.Destroyed
  else Ok ()

let float_max left right = if Float.compare left right >= 0 then left else right

let is_at_bottom box =
  let maximum = max 0.0 (box.content_height -. Renderable.height box.viewport) in
  Float.compare (Scroll_bar.scroll_position box.vertical_scrollbar) (maximum -. 0.01) >= 0

let is_at_right box =
  let maximum = max 0.0 (box.content_width -. Renderable.width box.viewport) in
  Float.compare (Scroll_bar.scroll_position box.horizontal_scrollbar) (maximum -. 0.01) >= 0

let apply_sticky_start box =
  match box.sticky_start with
  | None -> ()
  | Some Top -> ignore (Scroll_bar.set_scroll_position box.vertical_scrollbar 0.0)
  | Some Bottom ->
      ignore
        (Scroll_bar.set_scroll_position box.vertical_scrollbar
           (max 0.0 (box.content_height -. Renderable.height box.viewport)))
  | Some Left -> ignore (Scroll_bar.set_scroll_position box.horizontal_scrollbar 0.0)
  | Some Right ->
      ignore
        (Scroll_bar.set_scroll_position box.horizontal_scrollbar
           (max 0.0 (box.content_width -. Renderable.width box.viewport)))

let update_translation box =
  ignore
    (Renderable.set_translate_x box.content
       (-.Scroll_bar.scroll_position box.horizontal_scrollbar));
  ignore
    (Renderable.set_translate_y box.content
       (-.Scroll_bar.scroll_position box.vertical_scrollbar))

let update_scrollbars box =
  ignore
    (Scroll_bar.set_viewport_size box.vertical_scrollbar
       (Renderable.height box.viewport));
  ignore
    (Scroll_bar.set_viewport_size box.horizontal_scrollbar
       (Renderable.width box.viewport));
  ignore (Scroll_bar.set_scroll_size box.vertical_scrollbar box.content_height);
  ignore (Scroll_bar.set_scroll_size box.horizontal_scrollbar box.content_width);
  update_translation box

let compute_content_size box =
  let width = ref (if box.manual_content_size then box.content_width else 0.0) in
  let height = ref (if box.manual_content_size then box.content_height else 0.0) in
  List.iter
    (fun child ->
      match Renderable.layout child with
      | Error _ -> ()
      | Ok layout ->
          (* [Renderable.x]/[y] include all ancestor translations.  The
             content translation is the scroll offset, so using those
             accessors here would make the measured content shrink whenever
             the viewport scrolls.  Intrinsic content bounds are expressed in
             the child's parent coordinate system, just like the reference
             ContentRenderable's Yoga size. *)
          width := float_max !width (layout.left +. Renderable.width child);
          height := float_max !height (layout.top +. Renderable.height child))
    (Renderable.children box.content);
  let width = max 0.0 !width in
  let height = max 0.0 !height in
  let was_bottom = is_at_bottom box in
  let was_right = is_at_right box in
  if not (Float.equal width box.content_width) then begin
    box.content_width <- width;
    ignore (Renderable.set_width box.content (Yoga.Point width))
  end;
  if not (Float.equal height box.content_height) then begin
    box.content_height <- height;
    ignore (Renderable.set_height box.content (Yoga.Point height))
  end;
  update_scrollbars box;
  if box.sticky_scroll then begin
    if was_bottom then
      ignore
        (Scroll_bar.set_scroll_position box.vertical_scrollbar
           (max 0.0 (box.content_height -. Renderable.height box.viewport)));
    if was_right then
      ignore
        (Scroll_bar.set_scroll_position box.horizontal_scrollbar
           (max 0.0 (box.content_width -. Renderable.width box.viewport)))
  end;
  apply_sticky_start box;
  update_translation box

let visible_children box _renderable =
  if not box.viewport_culling then Renderable.children box.content
  else
    let objects : Renderable.t Lib.Objects_in_viewport.object_ list =
      List.map
        (fun child ->
          {
            Lib.Objects_in_viewport.value = child;
            screen_x = Renderable.screen_x child;
            screen_y = Renderable.screen_y child;
            width = Renderable.width child;
            height = Renderable.height child;
            z_index = Renderable.z_index child;
          })
        (Renderable.children box.content)
    in
    let viewport : Lib.Objects_in_viewport.viewport =
      {
        x = Renderable.screen_x box.viewport;
        y = Renderable.screen_y box.viewport;
        width = Renderable.width box.viewport;
        height = Renderable.height box.viewport;
      }
    in
      List.map (fun (object_ : Renderable.t Lib.Objects_in_viewport.object_) -> object_.value)
      (Lib.Objects_in_viewport.get ~direction:Lib.Objects_in_viewport.Column
         viewport objects)

let install_content_behavior box =
  let behavior =
    Renderable.Private.make_behavior
      ~filters_children:box.viewport_culling
      ~visible_children:(visible_children box) ()
  in
  Renderable.Private.set_behavior box.content behavior

let rec handle_scroll box event =
  match Renderable.mouse_scroll event with
  | None -> ()
  | Some scroll ->
      let multiplier = Lib.Scroll_acceleration.tick box.acceleration () in
      let delta = float_of_int scroll.delta *. multiplier in
      let shift = (Renderable.mouse_modifiers event).shift in
      let dx, dy =
        let direction =
          if not shift then scroll.direction
          else
            match scroll.direction with
            | Lib.Mouse_decoder.Scroll_up -> Lib.Mouse_decoder.Scroll_left
            | Lib.Mouse_decoder.Scroll_down -> Lib.Mouse_decoder.Scroll_right
            | Lib.Mouse_decoder.Scroll_left -> Lib.Mouse_decoder.Scroll_up
            | Lib.Mouse_decoder.Scroll_right -> Lib.Mouse_decoder.Scroll_down
        in
        match direction with
        | Lib.Mouse_decoder.Scroll_left -> -.delta, 0.0
        | Lib.Mouse_decoder.Scroll_right -> delta, 0.0
        | Lib.Mouse_decoder.Scroll_up -> 0.0, -.delta
        | Lib.Mouse_decoder.Scroll_down -> 0.0, delta
      in
      let consume value accumulator set_accumulator =
        let next = accumulator +. value in
        let whole = Float.trunc next in
        set_accumulator (next -. whole);
        whole
      in
      let dx =
        consume dx box.scroll_accumulator_x
          (fun value -> box.scroll_accumulator_x <- value)
      in
      let dy =
        consume dy box.scroll_accumulator_y
          (fun value -> box.scroll_accumulator_y <- value)
      in
      ignore (scroll_by box ~dx ~dy)

and scroll_by box ~dx ~dy =
  Result.bind (ensure_alive box) (fun () ->
      let result =
        if box.scroll_x then
          Scroll_bar.scroll_by box.horizontal_scrollbar dx Scroll_bar.Absolute
        else Ok ()
      in
      Result.bind result (fun () ->
          if box.scroll_y then
            Scroll_bar.scroll_by box.vertical_scrollbar dy Scroll_bar.Absolute
          else Ok ()))

let auto_scroll_direction_x box x =
  let left = Renderable.screen_x box.viewport in
  let right = left +. Renderable.width box.viewport in
  let relative = float_of_int x -. left in
  let distance_to_left = relative in
  let distance_to_right = right -. float_of_int x in
  let position = Scroll_bar.scroll_position box.horizontal_scrollbar in
  let maximum = max 0.0 (box.content_width -. Renderable.width box.viewport) in
  if Float.compare distance_to_left 3.0 <= 0 then
    if Float.compare position 0.0 > 0 then -1 else 0
  else if Float.compare distance_to_right 3.0 <= 0 then
    if Float.compare position maximum < 0 then 1 else 0
  else 0

let auto_scroll_direction_y box y =
  let top = Renderable.screen_y box.viewport in
  let bottom = top +. Renderable.height box.viewport in
  let distance_to_top = float_of_int y -. top in
  let distance_to_bottom = bottom -. float_of_int y in
  let position = Scroll_bar.scroll_position box.vertical_scrollbar in
  let maximum = max 0.0 (box.content_height -. Renderable.height box.viewport) in
  if Float.compare distance_to_top 3.0 <= 0 then
    if Float.compare position 0.0 > 0 then -1 else 0
  else if Float.compare distance_to_bottom 3.0 <= 0 then
    if Float.compare position maximum < 0 then 1 else 0
  else 0

let auto_scroll_speed box x y =
  let left = Renderable.screen_x box.viewport in
  let top = Renderable.screen_y box.viewport in
  let right = left +. Renderable.width box.viewport in
  let bottom = top +. Renderable.height box.viewport in
  let distances =
    [ float_of_int x -. left;
      right -. float_of_int x;
      float_of_int y -. top;
      bottom -. float_of_int y ]
  in
  let minimum = List.fold_left Float.min Float.infinity distances in
  if Float.compare minimum 1.0 <= 0 then 72.0
  else if Float.compare minimum 2.0 <= 0 then 36.0
  else 6.0

let stop_auto_scroll box =
  box.auto_scroll_active <- false;
  box.auto_scroll_pointer <- None;
  box.auto_scroll_accumulator_x <- 0.0;
  box.auto_scroll_accumulator_y <- 0.0;
  if box.auto_scroll_live_acquired then begin
    ignore
      (Render_context.drop_live (Renderable.context box.renderable));
    box.auto_scroll_live_acquired <- false
  end

let start_auto_scroll box ~x ~y =
  box.auto_scroll_pointer <- Some (x, y);
  box.auto_scroll_speed <- auto_scroll_speed box x y;
  if not box.auto_scroll_active then begin
    box.auto_scroll_active <- true;
    box.auto_scroll_accumulator_x <- 0.0;
    box.auto_scroll_accumulator_y <- 0.0;
    match Render_context.request_live (Renderable.context box.renderable) with
    | Ok () ->
        box.auto_scroll_live_acquired <- true
    | Error _ ->
        box.auto_scroll_active <- false
  end

let update_auto_scroll box ~x ~y =
  if box.selection_dragging then begin
    let direction_x = auto_scroll_direction_x box x in
    let direction_y = auto_scroll_direction_y box y in
    if Int.equal direction_x 0 && Int.equal direction_y 0 then
      stop_auto_scroll box
    else if box.auto_scroll_active then begin
      box.auto_scroll_pointer <- Some (x, y);
      box.auto_scroll_speed <- auto_scroll_speed box x y
    end
    else start_auto_scroll box ~x ~y
  end
  else stop_auto_scroll box

let handle_auto_scroll box delta_time =
  if box.auto_scroll_active && box.selection_dragging then
    match box.auto_scroll_pointer with
    | None -> stop_auto_scroll box
    | Some (x, y) ->
        let direction_x = auto_scroll_direction_x box x in
        let direction_y = auto_scroll_direction_y box y in
        if Int.equal direction_x 0 && Int.equal direction_y 0 then
          stop_auto_scroll box
        else if not (Float.is_finite delta_time)
                || Float.compare delta_time 0.0 < 0 then
          stop_auto_scroll box
        else begin
          let amount = box.auto_scroll_speed *. delta_time in
          box.auto_scroll_accumulator_x <-
            box.auto_scroll_accumulator_x
            +. (float_of_int direction_x *. amount);
          box.auto_scroll_accumulator_y <-
            box.auto_scroll_accumulator_y
            +. (float_of_int direction_y *. amount);
          let dx = Float.trunc box.auto_scroll_accumulator_x in
          let dy = Float.trunc box.auto_scroll_accumulator_y in
          box.auto_scroll_accumulator_x <-
            box.auto_scroll_accumulator_x -. dx;
          box.auto_scroll_accumulator_y <-
            box.auto_scroll_accumulator_y -. dy;
          let before_x = Scroll_bar.scroll_position box.horizontal_scrollbar in
          let before_y = Scroll_bar.scroll_position box.vertical_scrollbar in
          ignore (scroll_by box ~dx ~dy);
          let after_x = Scroll_bar.scroll_position box.horizontal_scrollbar in
          let after_y = Scroll_bar.scroll_position box.vertical_scrollbar in
          if not (Float.equal before_x after_x)
             || not (Float.equal before_y after_y)
          then begin
            ignore
              (Render_context.request_selection_update
                 (Renderable.context box.renderable))
          end
          else if not (Float.equal dx 0.0) || not (Float.equal dy 0.0) then
            stop_auto_scroll box
        end
  else if box.auto_scroll_active then stop_auto_scroll box

let handle_key_press box event =
  if box.scroll_y && Scroll_bar.handle_key_press box.vertical_scrollbar event then begin
    Lib.Scroll_acceleration.reset box.acceleration;
    box.scroll_accumulator_x <- 0.0;
    box.scroll_accumulator_y <- 0.0;
    true
  end else if box.scroll_x && Scroll_bar.handle_key_press box.horizontal_scrollbar event then begin
    Lib.Scroll_acceleration.reset box.acceleration;
    box.scroll_accumulator_x <- 0.0;
    box.scroll_accumulator_y <- 0.0;
    true
  end else false

let create context ?id ?(scroll_x = false) ?(scroll_y = true)
    ?(sticky_scroll = false) ?sticky_start ?(viewport_culling = true)
    ?(scroll_acceleration = Lib.Scroll_acceleration.linear ()) ?width ?height () =
  match Renderable.Private.create context ?id () with
  | Error error -> Error error
  | Ok renderable ->
      let cleanup () = Renderable.destroy renderable in
      let make_child ?id () = Renderable.Private.create context ?id () in
      (match make_child ?id:None () with
      | Error error -> cleanup (); Error error
      | Ok wrapper ->
          (match make_child ?id:None () with
          | Error error -> Renderable.destroy wrapper; cleanup (); Error error
          | Ok viewport ->
              (match make_child ?id:None () with
              | Error error -> Renderable.destroy viewport; Renderable.destroy wrapper; cleanup (); Error error
              | Ok content ->
                  let bars_result =
                    Scroll_bar.create context ~orientation:Scroll_bar.Vertical ()
                  in
                  (match bars_result with
                  | Error error -> Renderable.destroy content; Renderable.destroy viewport; Renderable.destroy wrapper; cleanup (); Error error
                  | Ok vertical_scrollbar ->
                      (match Scroll_bar.create context ~orientation:Scroll_bar.Horizontal () with
                      | Error error ->
                          Scroll_bar.destroy vertical_scrollbar;
                          Renderable.destroy content;
                          Renderable.destroy viewport;
                          Renderable.destroy wrapper;
                          cleanup ();
                          Error error
                      | Ok horizontal_scrollbar ->
                          let box =
                            {
                              renderable;
                              wrapper;
                              viewport;
                              content;
                              children = Layout_children.Private.of_renderable content;
                              vertical_scrollbar;
                              horizontal_scrollbar;
                              scroll_x;
                              scroll_y;
                              acceleration = scroll_acceleration;
                              sticky_scroll;
                              sticky_start;
                              viewport_culling;
                              content_width = 0.0;
                              content_height = 0.0;
                              manual_content_size = false;
                              scroll_accumulator_x = 0.0;
                              scroll_accumulator_y = 0.0;
                              auto_scroll_pointer = None;
                              auto_scroll_speed = 6.0;
                              auto_scroll_active = false;
                              auto_scroll_accumulator_x = 0.0;
                              auto_scroll_accumulator_y = 0.0;
                              auto_scroll_live_acquired = false;
                              selection_dragging = false;
                              selection_subscription = None;
                              destroyed = false;
                            }
                          in
                          install_content_behavior box;
                          let viewport_behavior =
                            Renderable.Private.make_behavior
                              ~on_resize:(fun _ ~width:_ ~height:_ ->
                                stop_auto_scroll box;
                                update_scrollbars box)
                              ~mouse_event:(fun _ event ->
                                match Renderable.mouse_kind event with
                                | Renderable.Scroll ->
                                    handle_scroll box event;
                                    Renderable.mouse_stop_propagation event
                                | _ -> ())
                              ~should_start_selection:(fun _ ~x ~y ->
                                x >= int_of_float (Float.floor (Renderable.screen_x viewport))
                                && y >= int_of_float (Float.floor (Renderable.screen_y viewport))
                                && x < int_of_float (Float.ceil (Renderable.screen_x viewport +. Renderable.width viewport))
                                && y < int_of_float (Float.ceil (Renderable.screen_y viewport +. Renderable.height viewport)))
                              ()
                          in
                          Renderable.Private.set_behavior viewport viewport_behavior;
                          let behavior =
                            Renderable.Private.make_behavior
                              ~on_update:(fun _ delta_time ->
                                handle_auto_scroll box delta_time)
                              ~on_visibility:(fun _ visible ->
                                if not visible then stop_auto_scroll box)
                              ~on_resize:(fun _ ~width:_ ~height:_ ->
                                stop_auto_scroll box;
                                update_scrollbars box)
                              ~key_press:(fun _ event -> ignore (handle_key_press box event))
                              ~mouse_event:(fun _ event ->
                                match Renderable.mouse_kind event with
                                | Renderable.Scroll ->
                                    handle_scroll box event;
                                    Renderable.mouse_stop_propagation event
                                | Renderable.Down | Renderable.Move
                                | Renderable.Drag ->
                                    update_auto_scroll box
                                      ~x:(Renderable.mouse_x event)
                                      ~y:(Renderable.mouse_y event)
                                | Renderable.Up | Renderable.Drag_end ->
                                    stop_auto_scroll box
                                | Renderable.Drop | Renderable.Over
                                | Renderable.Out -> ())
                              ~updates_each_frame:true
                              ~destroy_self:(fun _ ->
                                stop_auto_scroll box;
                                box.selection_dragging <- false;
                                Option.iter
                                  Event_subscription.cancel
                                  box.selection_subscription;
                                box.selection_subscription <- None;
                                Render_context.Private.unregister_post_layout_pass
                                  context ~id:(Renderable.num renderable);
                                box.destroyed <- true;
                                Scroll_bar.destroy vertical_scrollbar;
                                Scroll_bar.destroy horizontal_scrollbar;
                                Renderable.destroy content;
                                Renderable.destroy viewport;
                                Renderable.destroy wrapper)
                              ()
                          in
                          Renderable.Private.set_behavior renderable behavior;
                          ignore (Renderable.set_focusable renderable true);
                          ignore (Renderable.set_flex_direction renderable Yoga.Flex_row);
                          ignore (Renderable.set_align_items renderable Yoga.Align_stretch);
                          ignore (Renderable.set_flex_direction wrapper Yoga.Flex_column);
                          ignore (Renderable.set_flex_grow wrapper (Some 1.0));
                          ignore (Renderable.set_flex_shrink wrapper (Some 1.0));
                          ignore (Renderable.set_overflow viewport Yoga.Overflow_hidden);
                          ignore (Renderable.set_flex_grow viewport (Some 1.0));
                          ignore (Renderable.set_flex_shrink viewport (Some 1.0));
                          ignore (Renderable.set_align_self content Yoga.Align_flex_start);
                          ignore (Renderable.set_flex_shrink content (Some 0.0));
                          ignore (Renderable.set_min_width content (Yoga.Percent 100.0));
                          ignore (Renderable.set_min_height content (Yoga.Percent 100.0));
                          if not scroll_x then
                            ignore (Renderable.set_max_width content (Yoga.Percent 100.0));
                          if not scroll_y then
                            ignore (Renderable.set_max_height content (Yoga.Percent 100.0));
                          if scroll_y then
                            Scroll_bar.reset_visibility_control vertical_scrollbar
                          else
                            ignore (Scroll_bar.set_visible vertical_scrollbar false);
                          if scroll_x then
                            Scroll_bar.reset_visibility_control horizontal_scrollbar
                          else
                            ignore (Scroll_bar.set_visible horizontal_scrollbar false);
                          let result =
                            Renderable.Private.attach ~parent:renderable ~child:wrapper ~index:0
                          in
                          let result = Result.bind result (fun _ ->
                              Renderable.Private.attach ~parent:wrapper ~child:viewport ~index:0) in
                          let result = Result.bind result (fun _ ->
                              Renderable.Private.attach ~parent:viewport ~child:content ~index:0) in
                          let result = Result.bind result (fun _ ->
                              Renderable.Private.attach ~parent:renderable
                                ~child:(Scroll_bar.as_renderable vertical_scrollbar) ~index:1) in
                          let result = Result.bind result (fun _ ->
                              Renderable.Private.attach ~parent:wrapper
                                ~child:(Scroll_bar.as_renderable horizontal_scrollbar) ~index:1) in
                          let result = Result.bind result (fun _ ->
                              match width with None -> Ok () | Some value -> Renderable.set_width renderable value) in
                          let result = Result.bind result (fun () ->
                              match height with None -> Ok () | Some value -> Renderable.set_height renderable value) in
                          (match result with
                          | Error error -> Renderable.destroy_recursively renderable; Error error
                          | Ok () ->
                              Render_context.Private.register_post_layout_pass context
                                ~id:(Renderable.num renderable)
                                (fun () ->
                                  if not box.destroyed then
                                    compute_content_size box);
                              let bind_scroll bar =
                                ignore
                                  (Scroll_bar.on_change bar (fun _ ->
                                       update_translation box))
                              in
                              bind_scroll vertical_scrollbar;
                              bind_scroll horizontal_scrollbar;
                              apply_sticky_start box;
                              (match
                                 Render_context.on_selection context
                                   (fun selection ->
                                     match selection with
                                     | Some value
                                       when Lib.Selection.is_active value
                                            && Lib.Selection.is_dragging value ->
                                         box.selection_dragging <- true
                                     | Some _ | None ->
                                         box.selection_dragging <- false;
                                         stop_auto_scroll box)
                               with
                              | Error error ->
                                  Renderable.destroy_recursively renderable;
                                  Error error
                              | Ok subscription ->
                                  box.selection_subscription <- Some subscription;
                                  Ok box)))))))

let as_renderable box = box.renderable
let wrapper box = box.wrapper
let viewport box = box.viewport
let content box = box.content
let children box = box.children
let vertical_scrollbar box = box.vertical_scrollbar
let horizontal_scrollbar box = box.horizontal_scrollbar
let add ?index box child =
  Result.bind (ensure_alive box) (fun () -> Layout_children.add ?index box.children child)

let remove box child =
  Result.bind (ensure_alive box) (fun () -> Layout_children.remove box.children child)
let scroll_top box = Scroll_bar.scroll_position box.vertical_scrollbar
let scroll_left box = Scroll_bar.scroll_position box.horizontal_scrollbar
let scroll_width box = box.content_width
let scroll_height box = box.content_height
let viewport_width box = Renderable.width box.viewport
let viewport_height box = Renderable.height box.viewport
let set_scroll_top box value = Scroll_bar.set_scroll_position box.vertical_scrollbar value
let set_scroll_left box value = Scroll_bar.set_scroll_position box.horizontal_scrollbar value
let scroll_to box ~x ~y =
  Result.bind (set_scroll_left box x) (fun () -> set_scroll_top box y)

let rec contains_child parent target =
  List.exists
    (fun child ->
      child == target || contains_child child target)
    (Renderable.children parent)

let nearest_scroll_delta start finish viewport_start viewport_finish =
  let size = finish -. start in
  let viewport_size = viewport_finish -. viewport_start in
  let starts_before = Float.compare start viewport_start < 0 in
  let finishes_after = Float.compare finish viewport_finish > 0 in
  if starts_before && finishes_after then 0.0
  else if starts_before && Float.compare size viewport_size < 0 then
    start -. viewport_start
  else if finishes_after && Float.compare size viewport_size > 0 then
    start -. viewport_start
  else if starts_before && Float.compare size viewport_size > 0 then
    finish -. viewport_finish
  else if finishes_after && Float.compare size viewport_size < 0 then
    finish -. viewport_finish
  else 0.0

let scroll_child_into_view box child =
  Result.bind (ensure_alive box) (fun () ->
      if not (contains_child box.content child) then Error Error.Not_child
      else
        let child_left = Renderable.screen_x child in
        let child_right = child_left +. Renderable.width child in
        let child_top = Renderable.screen_y child in
        let child_bottom = child_top +. Renderable.height child in
        let viewport_left = Renderable.screen_x box.viewport in
        let viewport_right = viewport_left +. Renderable.width box.viewport in
        let viewport_top = Renderable.screen_y box.viewport in
        let viewport_bottom = viewport_top +. Renderable.height box.viewport in
        let dx =
          nearest_scroll_delta child_left child_right viewport_left viewport_right
        in
        let dy =
          nearest_scroll_delta child_top child_bottom viewport_top viewport_bottom
        in
        scroll_by box ~dx ~dy)
let scroll_by = scroll_by
let sticky_scroll box = box.sticky_scroll
let set_sticky_scroll box value =
  box.sticky_scroll <- value;
  if value then compute_content_size box
let sticky_start box = box.sticky_start
let set_sticky_start box value =
  box.sticky_start <- value;
  if box.sticky_scroll then apply_sticky_start box
let viewport_culling box = box.viewport_culling
let set_viewport_culling box value =
  box.viewport_culling <- value;
  install_content_behavior box;
  ignore (Renderable.request_render box.content)
let destroy box = if not box.destroyed then Renderable.destroy_recursively box.renderable
