type rect = {
  x : float;
  y : float;
  width : float;
  height : float;
}

type mouse_event_kind =
  | Down
  | Up
  | Move
  | Drag
  | Drag_end
  | Drop
  | Over
  | Out
  | Scroll

type mouse_event = {
  kind : mouse_event_kind;
  button : int;
  x : int;
  y : int;
  modifiers : Lib.Mouse_decoder.modifiers;
  scroll : Lib.Mouse_decoder.scroll option;
  source : t option;
  target : t option;
  mutable current_target : t option;
  is_dragging : bool;
  mutable default_prevented : bool;
  mutable propagation_stopped : bool;
}

and render_command =
  | Render of t
  | Push_opacity of float
  | Pop_opacity
  | Push_scissor of rect
  | Pop_scissor

and behavior = {
  on_update : t -> float -> unit;
  on_resize : t -> width:int -> height:int -> unit;
  on_remove : t -> unit;
  lifecycle_pass : (t -> unit) option;
  key_press : (t -> Lib.Key_handler.key_event -> unit) option;
  key_release : (t -> Lib.Key_handler.key_event -> unit) option;
  paste : (t -> Lib.Key_handler.paste_event -> unit) option;
  mouse_event : (t -> mouse_event -> unit) option;
  render_before : (t -> Buffer.t -> float -> (unit, Error.t) result) option;
  render_self : (t -> Buffer.t -> float -> (unit, Error.t) result) option;
  render_after : (t -> Buffer.t -> float -> (unit, Error.t) result) option;
  render_replacement :
    (t -> Buffer.t -> float -> (unit, Error.t) result) option;
  scissor_rect : t -> rect;
  visible_children : t -> t list;
  destroy_self : t -> unit;
  updates_each_frame : bool;
  custom_scissor : bool;
  filters_children : bool;
}

and t = {
  context : Render_context.t;
  num : int;
  mutable id : string;
  mutable parent : t option;
  mutable children_layout : t list;
  mutable children_z : t list;
  mutable z_index : int;
  mutable dirty : bool;
  mutable destroyed : bool;
  mutable visible : bool;
  mutable opacity : float;
  mutable focusable : bool;
  mutable focused : bool;
  mutable focused_descendant : bool;
  mutable on_key_down : (Lib.Key_handler.key_event -> unit) option;
  mutable on_key_release : (Lib.Key_handler.key_event -> unit) option;
  mutable on_paste : (Lib.Key_handler.paste_event -> unit) option;
  mutable on_mouse : (mouse_event -> unit) option;
  mutable on_mouse_down : (mouse_event -> unit) option;
  mutable on_mouse_up : (mouse_event -> unit) option;
  mutable on_mouse_move : (mouse_event -> unit) option;
  mutable on_mouse_drag : (mouse_event -> unit) option;
  mutable on_mouse_drag_end : (mouse_event -> unit) option;
  mutable on_mouse_drop : (mouse_event -> unit) option;
  mutable on_mouse_over : (mouse_event -> unit) option;
  mutable on_mouse_out : (mouse_event -> unit) option;
  mutable on_mouse_scroll : (mouse_event -> unit) option;
  mutable keypress_subscription : Event_subscription.t option;
  mutable keyrelease_subscription : Event_subscription.t option;
  mutable paste_subscription : Event_subscription.t option;
  mutable live : bool;
  mutable live_count : int;
  mutable translate_x : float;
  mutable translate_y : float;
  mutable x : float;
  mutable y : float;
  mutable screen_x : float;
  mutable screen_y : float;
  mutable width : float;
  mutable height : float;
  mutable flex_shrink : float;
  mutable cached_layout : Yoga.layout;
  mutable last_layout_frame : int64 option;
  mutable overflow : Yoga.overflow;
  mutable node : Yoga.Node.t option;
  mutable behavior : behavior;
  mutable is_root : bool;
  focused_events : unit Event_kernel.t;
  blurred_events : unit Event_kernel.t;
  destroyed_events : unit Event_kernel.t;
  resized_events : unit Event_kernel.t;
  layout_changed_events : unit Event_kernel.t;
  mutable render_list : render_command list;
  mutable applied_layout_generation : int64;
  mutable applied_render_list_revision : int64;
  mutable render_list_reusable : bool;
}

let next_num = ref 1

let fresh_num () =
  let result = !next_num in
  next_num := result + 1;
  result

let zero_layout =
  {
    Yoga.left = 0.0;
    top = 0.0;
    right = 0.0;
    bottom = 0.0;
    width = 0.0;
    height = 0.0;
  }

let map_native_error error =
  match error with
  | Native.Error.Closed -> Error.Closed
  | Native.Error.Native error -> Error.Native (Native.Error.Native error)

let map_native_result result =
  match result with
  | Ok value -> Ok value
  | Error error -> Error (map_native_error error)

let ensure_open renderable =
  if not (Render_context.Private.is_open renderable.context) then Error Error.Closed
  else if renderable.destroyed then Error Error.Destroyed
  else Ok ()

let ensure_queryable renderable =
  if not (Render_context.Private.is_open renderable.context) then Error Error.Closed
  else if renderable.destroyed then Error Error.Destroyed
  else Ok ()

let request_render_internal renderable =
  renderable.dirty <- true;
  Render_context.Private.request_render renderable.context

let bump_render_list_revision renderable =
  ignore
    (Render_context.Private.bump_render_list_revision renderable.context)

let invalidate_layout_cache renderable =
  renderable.last_layout_frame <- None

let request_render renderable =
  match ensure_open renderable with
  | Error error -> Error error
  | Ok () ->
      request_render_internal renderable;
      Ok ()

let default_scissor renderable =
  {
    x = renderable.screen_x;
    y = renderable.screen_y;
    width = renderable.width;
    height = renderable.height;
  }

let inset_rect (rect : rect) ~left ~top ~right ~bottom : rect =
  {
    x = rect.x +. left;
    y = rect.y +. top;
    width = Float.max 0.0 (rect.width -. left -. right);
    height = Float.max 0.0 (rect.height -. top -. bottom);
  }

let default_visible_children renderable =
  List.filter (fun child -> child.visible && not child.destroyed) renderable.children_z

let emit event renderable value = ignore (Event_kernel.emit event value)

let default_behavior =
  {
    on_update = (fun _ _ -> ());
    on_resize = (fun renderable ~width:_ ~height:_ ->
      emit renderable.resized_events renderable ();
      request_render_internal renderable);
    on_remove = (fun _ -> ());
    lifecycle_pass = None;
    key_press = None;
    key_release = None;
    paste = None;
    mouse_event = None;
    render_before = None;
    render_self = None;
    render_after = None;
    render_replacement = None;
    scissor_rect = default_scissor;
    visible_children = default_visible_children;
    destroy_self = (fun _ -> ());
    updates_each_frame = false;
    custom_scissor = false;
    filters_children = false;
  }

let make_behavior ?on_update ?on_resize ?on_remove ?lifecycle_pass ?key_press
    ?key_release ?paste ?mouse_event ?render_before ?render_self ?render_after
    ?render_replacement ?scissor_rect ?visible_children ?destroy_self
    ?(updates_each_frame = false) ?(custom_scissor = false)
    ?(filters_children = false) () =
  {
    on_update = Option.value on_update ~default:default_behavior.on_update;
    on_resize = Option.value on_resize ~default:default_behavior.on_resize;
    on_remove = Option.value on_remove ~default:default_behavior.on_remove;
    lifecycle_pass;
    key_press;
    key_release;
    paste;
    mouse_event;
    render_before;
    render_self;
    render_after;
    render_replacement;
    scissor_rect = Option.value scissor_rect ~default:default_behavior.scissor_rect;
    visible_children =
      Option.value visible_children ~default:default_behavior.visible_children;
    destroy_self = Option.value destroy_self ~default:default_behavior.destroy_self;
    updates_each_frame;
    custom_scissor;
    filters_children;
  }

let with_node renderable operation =
  match renderable.node with
  | None -> Error Error.Destroyed
  | Some node -> operation node

let create_node context ~id ~behavior ~is_root =
  if not (Render_context.Private.is_open context) then Error Error.Closed
  else
    match Yoga.Node.create () with
    | Error error -> Error (map_native_error error)
    | Ok node ->
        let renderable =
          {
            context;
            num = fresh_num ();
            id;
            parent = None;
            children_layout = [];
            children_z = [];
            z_index = 0;
            dirty = false;
            destroyed = false;
            visible = true;
            opacity = 1.0;
            focusable = false;
            focused = false;
            focused_descendant = false;
            on_key_down = None;
            on_key_release = None;
            on_paste = None;
            on_mouse = None;
            on_mouse_down = None;
            on_mouse_up = None;
            on_mouse_move = None;
            on_mouse_drag = None;
            on_mouse_drag_end = None;
            on_mouse_drop = None;
            on_mouse_over = None;
            on_mouse_out = None;
            on_mouse_scroll = None;
            keypress_subscription = None;
            keyrelease_subscription = None;
            paste_subscription = None;
            live = false;
            live_count = 0;
            translate_x = 0.0;
            translate_y = 0.0;
            x = 0.0;
            y = 0.0;
            screen_x = 0.0;
            screen_y = 0.0;
            width = 0.0;
            height = 0.0;
            flex_shrink = 1.0;
            cached_layout = zero_layout;
            last_layout_frame = None;
            overflow = Yoga.Overflow_visible;
            node = Some node;
            behavior;
            is_root;
            focused_events = Event_kernel.create ();
            blurred_events = Event_kernel.create ();
            destroyed_events = Event_kernel.create ();
            resized_events = Event_kernel.create ();
            layout_changed_events = Event_kernel.create ();
            render_list = [];
            applied_layout_generation = -1L;
            applied_render_list_revision = -1L;
            render_list_reusable = false;
          }
        in
        match Yoga.Node.set_display node Yoga.Display_flex with
        | Ok () ->
            (match Yoga.Node.set_flex_grow node (Some 0.0),
                  Yoga.Node.set_flex_shrink node (Some 1.0) with
            | Ok (), Ok () -> Ok renderable
            | Error error, _ | _, Error error ->
                ignore (Yoga.Node.free node);
                Error (map_native_error error))
        | Error error ->
            ignore (Yoga.Node.free node);
            Error (map_native_error error)

let set_behavior renderable behavior =
  let had_lifecycle = Option.is_some renderable.behavior.lifecycle_pass in
  if had_lifecycle then
    Render_context.Private.unregister_lifecycle_pass renderable.context
      ~id:renderable.num;
  renderable.behavior <- behavior;
  if Option.is_some behavior.lifecycle_pass && Option.is_some renderable.parent then
      Render_context.Private.register_lifecycle_pass renderable.context
      ~id:renderable.num
      (fun () ->
        if not renderable.destroyed then
          match renderable.behavior.lifecycle_pass with
          | None -> ()
          | Some callback -> callback renderable);
  bump_render_list_revision renderable;
  request_render_internal renderable

let mark_yoga_dirty renderable =
  match ensure_open renderable with
  | Error error -> Error error
  | Ok () ->
      (match
         with_node renderable (fun node ->
             map_native_result (Yoga.Node.mark_dirty node))
       with
      | Error error -> Error error
      | Ok () ->
          invalidate_layout_cache renderable;
          request_render_internal renderable;
          Ok ())

let rec update_live_count renderable delta =
  let old_count = renderable.live_count in
  renderable.live_count <- old_count + delta;
  match renderable.parent with
  | Some parent -> update_live_count parent delta
  | None when renderable.is_root ->
      if Int.equal old_count 0 && Int.compare renderable.live_count 0 > 0 then
        Render_context.Private.request_live renderable.context
      else if Int.compare old_count 0 > 0 && Int.equal renderable.live_count 0 then
        Render_context.Private.drop_live renderable.context
  | None -> ()

let mark_parent_order_dirty parent =
  invalidate_layout_cache parent;
  bump_render_list_revision parent;
  request_render_internal parent

let remove_physical child values =
  List.filter (fun current -> current != child) values

let split_at index values =
  let rec loop remaining before rest =
    if Int.compare remaining 0 <= 0 then List.rev before, rest
    else
      match rest with
      | [] -> List.rev before, []
      | value :: tail -> loop (remaining - 1) (value :: before) tail
  in
  loop index [] values

let direct_child_index parent child =
  let rec find index = function
    | [] -> None
    | current :: rest ->
        if current == child then Some index else find (index + 1) rest
  in
  find 0 parent.children_layout

let insert_layout_child values index child =
  let before, after = split_at index values in
  before @ (child :: after)

let list_nth_opt values index =
  if Int.compare index 0 < 0 then None
  else
    let rec find current = function
      | [] -> None
      | value :: rest ->
          if Int.equal current index then Some value
          else find (current + 1) rest
    in
    find 0 values

let move_same_parent ~parent ~child ~index =
  with_node parent (fun parent_node ->
      with_node child (fun child_node ->
          map_native_result
            (Yoga.Node.move_child ~parent:parent_node ~child:child_node
               ~index:(Int32.of_int index))))

let remove_from_z_order parent child =
  parent.children_z <- remove_physical child parent.children_z

let register_lifecycle_if_needed renderable =
  match renderable.behavior.lifecycle_pass with
  | None -> ()
  | Some _ ->
      Render_context.Private.register_lifecycle_pass renderable.context
        ~id:renderable.num
        (fun () ->
          if not renderable.destroyed then
            match renderable.behavior.lifecycle_pass with
            | None -> ()
            | Some callback -> callback renderable)

let detach_internal ~parent ~child =
  match direct_child_index parent child with
  | None -> Error Error.Not_child
  | Some index ->
      (match with_node parent (fun parent_node ->
           with_node child (fun child_node ->
               map_native_result
                 (Yoga.Node.remove_child ~parent:parent_node ~child:child_node))) with
      | Error error -> Error error
      | Ok () ->
          if Int.compare child.live_count 0 > 0 then
            update_live_count parent (-child.live_count);
          parent.children_layout <-
            List.filteri
              (fun current _ -> not (Int.equal current index))
              parent.children_layout;
          remove_from_z_order parent child;
          invalidate_layout_cache parent;
          child.behavior.on_remove child;
          child.parent <- None;
          Render_context.Private.unregister_lifecycle_pass parent.context
            ~id:child.num;
          mark_parent_order_dirty parent;
          Ok ())

let check_attach parent child =
  match ensure_open parent with
  | Error error -> Error error
  | Ok () ->
      (match ensure_open child with
      | Error error -> Error error
      | Ok () ->
          if not (Render_context.same_owner parent.context child.context) then
            Error Error.Owner_mismatch
          else if parent == child then Error Error.Invalid_anchor
          else
            let rec contains_child current =
              match current.parent with
              | None -> false
              | Some ancestor_node ->
                  if ancestor_node == child then true
                  else contains_child ancestor_node
            in
            if contains_child parent then Error Error.Invalid_anchor else Ok ())

let rec attach_internal ~parent ~child ~index =
  match check_attach parent child with
  | Error error -> Error error
  | Ok () ->
      let same_parent =
        match child.parent with Some current -> current == parent | None -> false
      in
      if same_parent then begin
        match direct_child_index parent child with
        | None -> Error Error.Not_child
        | Some current_index ->
            let original = parent.children_layout in
            let anchor =
              if Int.compare index 0 >= 0
                 && Int.compare index (List.length original) < 0 then
                list_nth_opt original index
              else None
            in
            (match anchor with
            | Some current when current == child -> Ok current_index
            | _ ->
                let remaining = remove_physical child original in
                let target =
                  match anchor with
                  | None -> List.length remaining
                  | Some anchor ->
                      Option.value
                        (direct_child_index
                           { parent with children_layout = remaining }
                           anchor)
                        ~default:(List.length remaining)
                in
                match move_same_parent ~parent ~child ~index:target with
            | Error error -> Error error
            | Ok () ->
                parent.children_layout <- insert_layout_child remaining target child;
                mark_parent_order_dirty parent;
                Ok target)
      end else begin
        match child.parent with
        | Some old_parent ->
            (match detach_internal ~parent:old_parent ~child with
            | Error error -> Error error
            | Ok () -> attach_internal ~parent ~child ~index)
        | None ->
            let target =
              if Int.compare index 0 >= 0
                 && Int.compare index (List.length parent.children_layout) < 0 then
                index
              else List.length parent.children_layout
            in
            (match with_node parent (fun parent_node ->
                 with_node child (fun child_node ->
                     map_native_result
                       (Yoga.Node.insert_child ~parent:parent_node ~child:child_node
                          ~index:(Int32.of_int target)))) with
            | Error error -> Error error
            | Ok () ->
                let before, after =
                  split_at target parent.children_layout
                in
                parent.children_layout <- before @ (child :: after);
                parent.children_z <- parent.children_z @ [ child ];
                child.parent <- Some parent;
                register_lifecycle_if_needed child;
                if Int.compare child.live_count 0 > 0 then
                  update_live_count parent child.live_count;
                mark_parent_order_dirty parent;
                Ok target)
      end

let rec insert_before_internal ~parent ~child ~anchor =
  match check_attach parent child with
  | Error error -> Error error
  | Ok () ->
      (match direct_child_index parent anchor with
      | None -> Error Error.Invalid_anchor
      | Some anchor_index when anchor == child -> Error Error.Invalid_anchor
      | Some anchor_index ->
          let old_parent = child.parent in
          (match old_parent with
          | Some current ->
              if current == parent then
                (match
                   let remaining = remove_physical child parent.children_layout in
                   match direct_child_index
                           { parent with children_layout = remaining }
                           anchor with
                   | None -> Error Error.Invalid_anchor
                   | Some target -> move_same_parent ~parent ~child ~index:target
                 with
                | Error error -> Error error
                | Ok () ->
                    let remaining = remove_physical child parent.children_layout in
                    let target =
                      Option.value
                        (direct_child_index
                           { parent with children_layout = remaining }
                           anchor)
                        ~default:(List.length remaining)
                    in
                    parent.children_layout <-
                      insert_layout_child remaining target child;
                    mark_parent_order_dirty parent;
                    Ok target)
              else
                (match detach_internal ~parent:current ~child with
                | Error error -> Error error
                | Ok () -> insert_before_internal ~parent ~child ~anchor)
          | None ->
              (match with_node parent (fun parent_node ->
                   with_node child (fun child_node ->
                       map_native_result
                         (Yoga.Node.insert_child ~parent:parent_node ~child:child_node
                            ~index:(Int32.of_int anchor_index)))) with
              | Error error -> Error error
              | Ok () ->
                  let before, after =
                    split_at anchor_index parent.children_layout
                  in
                  parent.children_layout <- before @ (child :: after);
                  parent.children_z <- parent.children_z @ [ child ];
                  child.parent <- Some parent;
                  register_lifecycle_if_needed child;
                  if Int.compare child.live_count 0 > 0 then
                    update_live_count parent child.live_count;
                  mark_parent_order_dirty parent;
                  Ok anchor_index)))

let rec find_descendant renderable id =
  let rec search = function
    | [] -> None
    | child :: rest ->
        if String.equal child.id id then Some child
        else
          match find_descendant child id with
          | Some found -> Some found
          | None -> search rest
  in
  search renderable.children_layout

let rec find_by_num renderable target_num =
  if Int.equal renderable.num target_num then Some renderable
  else
    let rec search = function
      | [] -> None
      | child :: rest ->
          (match find_by_num child target_num with
          | Some found -> Some found
          | None -> search rest)
    in
    search renderable.children_layout

let ensure_event_source renderable =
  match ensure_open renderable with
  | Error error -> Error error
  | Ok () -> Ok ()

let register_event renderable channel register callback =
  match ensure_event_source renderable with
  | Error error -> Error error
  | Ok () -> Ok (register channel callback)

let update_from_layout renderable =
  match renderable.node with
  | None -> Error Error.Destroyed
  | Some node ->
      let frame_id =
        match Render_context.frame_id renderable.context with
        | Ok value -> value
        | Error _ -> -1L
      in
      (match renderable.last_layout_frame with
      | Some previous when Int64.equal previous frame_id -> Ok ()
      | Some _ | None ->
          (match Yoga.Node.layout node with
          | Error error -> Error (map_native_error error)
          | Ok layout ->
              let old_width = renderable.width in
              let old_height = renderable.height in
              let old_x = renderable.x in
              let old_y = renderable.y in
              renderable.cached_layout <- layout;
              renderable.x <- layout.left;
              renderable.y <- layout.top;
              renderable.width <- max layout.width 1.0;
              renderable.height <- max layout.height 1.0;
              let parent_x, parent_y =
                match renderable.parent with
                | None -> 0.0, 0.0
                | Some parent -> parent.screen_x, parent.screen_y
              in
              renderable.screen_x <-
                parent_x +. renderable.x +. renderable.translate_x;
              renderable.screen_y <-
                parent_y +. renderable.y +. renderable.translate_y;
              renderable.last_layout_frame <- Some frame_id;
              if not (Float.equal old_x renderable.x)
                 || not (Float.equal old_y renderable.y) then
                Option.iter
                  (fun parent -> invalidate_layout_cache parent)
                  renderable.parent;
              if renderable.visible
                 && (not (Float.equal old_width renderable.width)
                    || not (Float.equal old_height renderable.height)) then
                renderable.behavior.on_resize renderable
                  ~width:(int_of_float renderable.width)
                  ~height:(int_of_float renderable.height);
              Ok ()))

let ensure_z_sorted renderable =
  renderable.children_z <-
    List.stable_sort
      (fun left right -> Int.compare left.z_index right.z_index)
      renderable.children_z

let should_push_scissor renderable =
  (match renderable.overflow with
  | Yoga.Overflow_visible -> false
  | Yoga.Overflow_hidden | Yoga.Overflow_scroll -> true)
  && Float.compare renderable.width 0.0 > 0
  && Float.compare renderable.height 0.0 > 0

let rec collect_commands renderable ~delta_time commands =
  if not renderable.visible || renderable.destroyed then Ok ()
  else begin
    renderable.behavior.on_update renderable delta_time;
    if renderable.destroyed then Ok ()
    else
      match update_from_layout renderable with
      | Error error -> Error error
      | Ok () when renderable.destroyed -> Ok ()
      | Ok () ->
          let add command = commands := command :: !commands in
          let push_opacity = Float.compare renderable.opacity 1.0 < 0 in
          ensure_z_sorted renderable;
          let rec collect_children = function
            | [] -> Ok ()
            | child :: rest ->
                (match collect_commands child ~delta_time commands with
                | Error error -> Error error
                | Ok () -> collect_children rest)
          in
          let children_result =
            if not renderable.behavior.filters_children then Ok renderable.children_z
            else
              let rec refresh = function
                | [] -> Ok ()
                | child :: rest ->
                    (match update_from_layout child with
                    | Error error -> Error error
                    | Ok () -> refresh rest)
              in
              Result.bind (refresh renderable.children_z) (fun () ->
                  let visible = renderable.behavior.visible_children renderable in
                  Ok
                    (List.filter
                       (fun child ->
                         not child.destroyed
                         && List.exists
                              (fun candidate -> candidate == child)
                              visible)
                       renderable.children_z))
          in
          Result.bind children_result (fun children ->
              if renderable.destroyed then Ok ()
              else begin
                if push_opacity then add (Push_opacity renderable.opacity);
                add (Render renderable);
                if should_push_scissor renderable then begin
                  add (Push_scissor (renderable.behavior.scissor_rect renderable));
                  match collect_children children with
                  | Error error -> Error error
                  | Ok () ->
                      add Pop_scissor;
                      if push_opacity then add Pop_opacity;
                      Ok ()
                end else
                  match collect_children children with
                  | Error error -> Error error
                  | Ok () ->
                      if push_opacity then add Pop_opacity;
                      Ok ()
              end)
  end

let can_reuse_renderable renderable =
  (not renderable.behavior.updates_each_frame)
  && ((match renderable.overflow with
      | Yoga.Overflow_visible -> true
      | Yoga.Overflow_hidden | Yoga.Overflow_scroll -> false)
     || not renderable.behavior.custom_scissor)
  && not renderable.behavior.filters_children

let execute_render_command buffer ~delta_time = function
  | Push_opacity _ | Pop_opacity | Push_scissor _ | Pop_scissor ->
      Error Error.Unsupported
  | Render renderable ->
      if renderable.destroyed then Ok ()
      else
        let behavior = renderable.behavior in
        let run_default () =
          match behavior.render_before with
          | None -> Ok ()
          | Some callback -> callback renderable buffer delta_time
        in
        let run_self () =
          match behavior.render_self with
          | None -> Ok ()
          | Some callback -> callback renderable buffer delta_time
        in
        let run_after () =
          match behavior.render_after with
          | None -> Ok ()
          | Some callback -> callback renderable buffer delta_time
        in
        let result =
          match behavior.render_replacement with
          | Some callback -> callback renderable buffer delta_time
          | None ->
              (match run_default () with
              | Error error -> Error error
              | Ok () ->
                  (match run_self () with
                  | Error error -> Error error
                  | Ok () -> run_after ()))
        in
        (match result with
        | Error error -> Error error
        | Ok () ->
            renderable.dirty <- false;
            Render_context.Private.add_hit_grid renderable.context
              ~x:(int_of_float renderable.screen_x)
              ~y:(int_of_float renderable.screen_y)
              ~width:(int_of_float renderable.width)
              ~height:(int_of_float renderable.height)
              ~id:renderable.num;
            Ok ())

let calculate_root_layout root =
  match root.node with
  | None -> Error Error.Destroyed
  | Some node ->
      (match Render_context.width root.context, Render_context.height root.context with
      | Ok width, Ok height ->
          (match
             Yoga.Node.calculate_layout node ~width:(Int32.to_float width)
               ~height:(Int32.to_float height) ~direction:Yoga.Ltr
           with
          | Error error -> Error (map_native_error error)
          | Ok () ->
              ignore
                (Render_context.Private.bump_layout_generation root.context);
              (match Yoga.Node.mark_layout_seen node with
              | Error error -> Error (map_native_error error)
              | Ok () ->
                  invalidate_layout_cache root;
                  emit root.layout_changed_events root ();
                  Ok ()))
      | Error error, _ | _, Error error -> Error error)

let render_root root buffer ~delta_time =
  match ensure_queryable root with
  | Error error -> Error error
  | Ok () ->
      List.iter
        (fun callback -> callback ())
        (Render_context.Private.lifecycle_passes root.context);
      let layout_result =
        match root.node with
        | None -> Error Error.Destroyed
        | Some node ->
            (match Yoga.Node.is_dirty node with
            | Error error -> Error (map_native_error error)
            | Ok true -> calculate_root_layout root
            | Ok false ->
                (match Yoga.Node.has_new_layout node with
                | Error error -> Error (map_native_error error)
                | Ok false -> Ok ()
                | Ok true ->
                    ignore
                      (Render_context.Private.bump_layout_generation root.context);
                    (match Yoga.Node.mark_layout_seen node with
                    | Ok () ->
                        invalidate_layout_cache root;
                        emit root.layout_changed_events root ();
                        Ok ()
                    | Error error -> Error (map_native_error error))))
      in
      match layout_result with
      | Error error -> Error error
      | Ok () ->
        let layout_generation =
          Render_context.Private.layout_generation root.context
        in
        let render_list_revision =
          Render_context.Private.render_list_revision root.context
        in
        let can_reuse =
          root.render_list_reusable
          && Int64.equal root.applied_layout_generation layout_generation
          && Int64.equal root.applied_render_list_revision render_list_revision
        in
        let rebuild_result =
          if not can_reuse then begin
            let commands = ref [] in
            match collect_commands root ~delta_time commands with
            | Error error -> Error error
            | Ok () ->
                root.render_list <- List.rev !commands;
                root.applied_layout_generation <- layout_generation;
                root.applied_render_list_revision <-
                  Render_context.Private.render_list_revision root.context;
                root.render_list_reusable <-
                  Int.equal root.live_count 0
                  && List.for_all
                       (function
                         | Render renderable -> can_reuse_renderable renderable
                         | Push_opacity _ | Pop_opacity | Push_scissor _ | Pop_scissor ->
                             true)
                       root.render_list;
                Ok ()
          end else Ok ()
        in
        Result.bind rebuild_result (fun () ->
            Render_context.Private.clear_hit_grid root.context;
            let rec execute = function
              | [] -> Ok ()
              | command :: rest ->
                  (match execute_render_command buffer ~delta_time command with
                  | Error error -> Error error
                  | Ok () -> execute rest)
            in
            match root.render_list with
            | [] -> Ok ()
            | commands ->
                let rec execute_without_root = function
                  | [] -> Ok ()
                  | Render renderable :: rest when renderable == root ->
                      execute rest
                  | command :: rest ->
                      (match execute_render_command buffer ~delta_time command with
                      | Error error -> Error error
                      | Ok () -> execute_without_root rest)
                in
                execute_without_root commands)

let rec propagate_focus_change renderable value =
  match renderable.parent with
  | None -> ()
  | Some parent ->
      if not (Bool.equal parent.focused_descendant value) then begin
        parent.focused_descendant <- value;
        parent.dirty <- true
      end;
      propagate_focus_change parent value

let cancel_keyboard_handlers renderable =
  Option.iter Event_subscription.cancel renderable.keypress_subscription;
  Option.iter Event_subscription.cancel renderable.keyrelease_subscription;
  Option.iter Event_subscription.cancel renderable.paste_subscription;
  renderable.keypress_subscription <- None;
  renderable.keyrelease_subscription <- None;
  renderable.paste_subscription <- None

let install_keyboard_handlers renderable =
  let handler = Render_context.Private.key_handler renderable.context in
  let keypress_subscription =
    Lib.Key_handler.on_internal_keypress handler ~owner_num:renderable.num
      (fun event ->
        if not renderable.destroyed then begin
          Option.iter (fun callback -> callback event) renderable.on_key_down;
          if not renderable.destroyed
             && not (Lib.Key_handler.default_prevented event) then
            Option.iter
              (fun callback -> callback renderable event)
              renderable.behavior.key_press
        end)
  in
  let keyrelease_subscription =
    Lib.Key_handler.on_internal_keyrelease handler ~owner_num:renderable.num
      (fun event ->
        if not renderable.destroyed then begin
          Option.iter (fun callback -> callback event) renderable.on_key_release;
          if not renderable.destroyed
             && not (Lib.Key_handler.default_prevented event) then
            Option.iter
              (fun callback -> callback renderable event)
              renderable.behavior.key_release
        end)
  in
  let paste_subscription =
    Lib.Key_handler.on_internal_paste handler ~owner_num:renderable.num
      (fun event ->
        if not renderable.destroyed then begin
          Option.iter (fun callback -> callback event) renderable.on_paste;
          if not renderable.destroyed
             && not (Lib.Key_handler.paste_default_prevented event) then
            Option.iter
              (fun callback -> callback renderable event)
              renderable.behavior.paste
        end)
  in
  renderable.keypress_subscription <- Some keypress_subscription;
  renderable.keyrelease_subscription <- Some keyrelease_subscription;
  renderable.paste_subscription <- Some paste_subscription

let blur_state renderable =
  if renderable.focused && renderable.focusable then begin
    cancel_keyboard_handlers renderable;
    Render_context.Private.blur_renderable renderable.context ~id:renderable.num;
    renderable.focused <- false;
    propagate_focus_change renderable false;
    request_render_internal renderable;
    emit renderable.blurred_events renderable ()
  end else cancel_keyboard_handlers renderable

let mouse_handler renderable kind =
  match kind with
  | Down -> renderable.on_mouse_down
  | Up -> renderable.on_mouse_up
  | Move -> renderable.on_mouse_move
  | Drag -> renderable.on_mouse_drag
  | Drag_end -> renderable.on_mouse_drag_end
  | Drop -> renderable.on_mouse_drop
  | Over -> renderable.on_mouse_over
  | Out -> renderable.on_mouse_out
  | Scroll -> renderable.on_mouse_scroll

let rec process_mouse_event renderable event =
  event.current_target <- Some renderable;
  Option.iter (fun callback -> callback event) renderable.on_mouse;
  Option.iter (fun callback -> callback event) (mouse_handler renderable event.kind);
  Option.iter
    (fun callback -> callback renderable event)
    renderable.behavior.mouse_event;
  match renderable.parent with
  | Some parent when not event.propagation_stopped ->
      process_mouse_event parent event
  | Some _ | None -> ()

let make_mouse_event ~kind ~button ~x ~y ~modifiers ~scroll ~source ~target
    ~is_dragging =
  {
    kind;
    button;
    x;
    y;
    modifiers;
    scroll;
    source;
    target;
    current_target = None;
    is_dragging;
    default_prevented = false;
    propagation_stopped = false;
  }

let mouse_kind event = event.kind
let mouse_button event = event.button
let mouse_x event = event.x
let mouse_y event = event.y
let mouse_modifiers event = event.modifiers
let mouse_scroll event = event.scroll
let mouse_source event = event.source
let mouse_target event = event.target
let mouse_current_target event = event.current_target
let mouse_is_dragging event = event.is_dragging
let mouse_default_prevented event = event.default_prevented
let mouse_stop_propagation event = event.propagation_stopped <- true
let mouse_prevent_default event = event.default_prevented <- true
let mouse_propagation_stopped event = event.propagation_stopped

let set_key_listener renderable setter value =
  match ensure_open renderable with
  | Error error -> Error error
  | Ok () ->
      setter value;
      Ok ()

let set_mouse_listener renderable setter value =
  match ensure_open renderable with
  | Error error -> Error error
  | Ok () ->
      setter value;
      Ok ()

let detach_children renderable =
  List.iter
    (fun child -> ignore (detach_internal ~parent:renderable ~child))
    (List.rev renderable.children_layout);
  if Int.equal (List.length renderable.children_layout) 0 then begin
    renderable.children_layout <- [];
    renderable.children_z <- []
  end

let destroy renderable =
  if not renderable.destroyed then begin
    renderable.destroyed <- true;
    emit renderable.destroyed_events renderable ();
    Option.iter
      (fun parent -> ignore (detach_internal ~parent ~child:renderable))
      renderable.parent;
    detach_children renderable;
    blur_state renderable;
    Event_kernel.clear renderable.focused_events;
    Event_kernel.clear renderable.blurred_events;
    Event_kernel.clear renderable.resized_events;
    Event_kernel.clear renderable.layout_changed_events;
    renderable.behavior.destroy_self renderable;
    Event_kernel.clear renderable.destroyed_events
  end else begin
    Option.iter
      (fun parent -> ignore (detach_internal ~parent ~child:renderable))
      renderable.parent;
    detach_children renderable;
    blur_state renderable
  end;
  match renderable.node with
  | None -> ()
  | Some node ->
      (match Yoga.Node.free node with
      | Ok () -> renderable.node <- None
      | Error _ -> ())

let rec destroy_recursively renderable =
  List.iter destroy_recursively (List.rev renderable.children_layout);
  destroy renderable

let id renderable = renderable.id

let set_id renderable value =
  match ensure_open renderable with
  | Error error -> Error error
  | Ok () ->
      renderable.id <- value;
      Ok ()

let num renderable = renderable.num
let context renderable = renderable.context
let parent renderable = renderable.parent
let children renderable = renderable.children_layout
let child_count renderable = List.length renderable.children_layout

let find_child_by_id renderable value =
  List.find_opt (fun child -> String.equal child.id value) renderable.children_layout

let find_descendant_by_id renderable value = find_descendant renderable value
let is_destroyed renderable = renderable.destroyed
let is_dirty renderable = renderable.dirty
let visible renderable = renderable.visible

let set_visible renderable value =
  match ensure_open renderable with
  | Error error -> Error error
  | Ok () when Bool.equal renderable.visible value -> Ok ()
  | Ok () ->
      let was_visible = renderable.visible in
      renderable.visible <- value;
      let style_result =
        with_node renderable (fun node ->
            map_native_result
              (Yoga.Node.set_display node
                 (if value then Yoga.Display_flex else Yoga.Display_none)))
      in
      (match style_result with
      | Error error ->
          renderable.visible <- was_visible;
          Error error
      | Ok () ->
          bump_render_list_revision renderable;
          if renderable.live then
            if (not was_visible) && value then update_live_count renderable 1
            else if was_visible && not value then update_live_count renderable (-1);
          blur_state renderable;
          invalidate_layout_cache renderable;
          request_render renderable)

let opacity renderable = renderable.opacity

let set_opacity renderable value =
  match ensure_open renderable with
  | Error error -> Error error
  | Ok () ->
      let clamped = max 0.0 (min 1.0 value) in
      if Float.equal renderable.opacity clamped then Ok ()
      else begin
        renderable.opacity <- clamped;
        bump_render_list_revision renderable;
        request_render renderable
      end

let z_index renderable = renderable.z_index

let set_z_index renderable value =
  match ensure_open renderable with
  | Error error -> Error error
  | Ok () when Int.equal renderable.z_index value -> Ok ()
  | Ok () ->
      renderable.z_index <- value;
      bump_render_list_revision renderable;
      request_render renderable

let focusable renderable = renderable.focusable

let set_focusable renderable value =
  match ensure_open renderable with
  | Error error -> Error error
  | Ok () ->
      renderable.focusable <- value;
      Ok ()

let focused renderable = renderable.focused

let focus renderable =
  match ensure_open renderable with
  | Error error -> Error error
  | Ok () when renderable.focused || not renderable.focusable -> Ok ()
  | Ok () ->
      renderable.focused <- true;
      Render_context.Private.focus_renderable renderable.context
        ~id:renderable.num ~blur:(fun () -> blur_state renderable);
      install_keyboard_handlers renderable;
      propagate_focus_change renderable true;
      request_render renderable
      |> Result.map (fun () -> emit renderable.focused_events renderable ())

let blur renderable =
  match ensure_open renderable with
  | Error error -> Error error
  | Ok () when not renderable.focused || not renderable.focusable -> Ok ()
  | Ok () ->
      blur_state renderable;
      Ok ()

let set_on_key_down renderable callback =
  set_key_listener renderable
    (fun value -> renderable.on_key_down <- value)
    callback

let set_on_key_release renderable callback =
  set_key_listener renderable
    (fun value -> renderable.on_key_release <- value)
    callback

let set_on_paste renderable callback =
  set_key_listener renderable
    (fun value -> renderable.on_paste <- value)
    callback

let set_on_mouse renderable callback =
  set_mouse_listener renderable (fun value -> renderable.on_mouse <- value) callback

let set_on_mouse_down renderable callback =
  set_mouse_listener renderable
    (fun value -> renderable.on_mouse_down <- value)
    callback

let set_on_mouse_up renderable callback =
  set_mouse_listener renderable
    (fun value -> renderable.on_mouse_up <- value)
    callback

let set_on_mouse_move renderable callback =
  set_mouse_listener renderable
    (fun value -> renderable.on_mouse_move <- value)
    callback

let set_on_mouse_drag renderable callback =
  set_mouse_listener renderable
    (fun value -> renderable.on_mouse_drag <- value)
    callback

let set_on_mouse_drag_end renderable callback =
  set_mouse_listener renderable
    (fun value -> renderable.on_mouse_drag_end <- value)
    callback

let set_on_mouse_drop renderable callback =
  set_mouse_listener renderable
    (fun value -> renderable.on_mouse_drop <- value)
    callback

let set_on_mouse_over renderable callback =
  set_mouse_listener renderable
    (fun value -> renderable.on_mouse_over <- value)
    callback

let set_on_mouse_out renderable callback =
  set_mouse_listener renderable
    (fun value -> renderable.on_mouse_out <- value)
    callback

let set_on_mouse_scroll renderable callback =
  set_mouse_listener renderable
    (fun value -> renderable.on_mouse_scroll <- value)
    callback

let has_focused_descendant renderable = renderable.focused_descendant
let live renderable = renderable.live
let live_count renderable = renderable.live_count

let set_live renderable value =
  match ensure_open renderable with
  | Error error -> Error error
  | Ok () when Bool.equal renderable.live value -> Ok ()
  | Ok () ->
      renderable.live <- value;
      if renderable.visible then update_live_count renderable (if value then 1 else -1);
      Ok ()

let width renderable = renderable.width
let height renderable = renderable.height
let rec x renderable =
  match renderable.parent with
  | None -> renderable.x +. renderable.translate_x
  | Some parent -> x parent +. renderable.x +. renderable.translate_x

let rec y renderable =
  match renderable.parent with
  | None -> renderable.y +. renderable.translate_y
  | Some parent -> y parent +. renderable.y +. renderable.translate_y
let screen_x renderable =
  match renderable.parent with
  | None -> renderable.x +. renderable.translate_x
  | Some parent -> parent.screen_x +. renderable.x +. renderable.translate_x

let screen_y renderable =
  match renderable.parent with
  | None -> renderable.y +. renderable.translate_y
  | Some parent -> parent.screen_y +. renderable.y +. renderable.translate_y

let layout renderable =
  match ensure_queryable renderable with
  | Error error -> Error error
  | Ok () -> Ok renderable.cached_layout

let set_translate_x renderable value =
  match ensure_open renderable with
  | Error error -> Error error
  | Ok () when Float.equal renderable.translate_x value -> Ok ()
  | Ok () ->
      renderable.translate_x <- value;
      let parent_x =
        match renderable.parent with
        | None -> 0.0
        | Some parent -> parent.screen_x
      in
      renderable.screen_x <- parent_x +. renderable.x +. value;
      bump_render_list_revision renderable;
      request_render renderable

let set_translate_y renderable value =
  match ensure_open renderable with
  | Error error -> Error error
  | Ok () when Float.equal renderable.translate_y value -> Ok ()
  | Ok () ->
      renderable.translate_y <- value;
      let parent_y =
        match renderable.parent with
        | None -> 0.0
        | Some parent -> parent.screen_y
      in
      renderable.screen_y <- parent_y +. renderable.y +. value;
      bump_render_list_revision renderable;
      request_render renderable

let translate_x renderable = renderable.translate_x
let translate_y renderable = renderable.translate_y

let style_operation renderable operation =
  match ensure_open renderable with
  | Error error -> Error error
  | Ok () ->
      (match with_node renderable operation with
      | Error error -> Error error
      | Ok () ->
          invalidate_layout_cache renderable;
          request_render renderable)

let set_dimension renderable value setter =
  style_operation renderable (fun node ->
      match map_native_result (setter node) with
      | Error error -> Error error
      | Ok () when
          (match value with Yoga.Point _ -> true | Yoga.Undefined | Yoga.Percent _ | Yoga.Auto -> false)
          && Float.equal renderable.flex_shrink 1.0 ->
          (match
             map_native_result (Yoga.Node.set_flex_shrink node (Some 0.0))
           with
          | Error error -> Error error
          | Ok () ->
              renderable.flex_shrink <- 0.0;
              Ok ())
      | Ok () -> Ok ())

let set_width renderable value =
  set_dimension renderable value (fun node -> Yoga.Node.set_width node value)

let set_height renderable value =
  set_dimension renderable value (fun node -> Yoga.Node.set_height node value)

let set_min_width renderable value =
  style_operation renderable (fun node -> map_native_result (Yoga.Node.set_min_width node value))

let set_min_height renderable value =
  style_operation renderable (fun node -> map_native_result (Yoga.Node.set_min_height node value))

let set_max_width renderable value =
  style_operation renderable (fun node -> map_native_result (Yoga.Node.set_max_width node value))

let set_max_height renderable value =
  style_operation renderable (fun node -> map_native_result (Yoga.Node.set_max_height node value))

let set_flex_basis renderable value =
  style_operation renderable (fun node -> map_native_result (Yoga.Node.set_flex_basis node value))

let set_margin renderable ~edge value =
  style_operation renderable (fun node -> map_native_result (Yoga.Node.set_margin node ~edge value))

let set_padding renderable ~edge value =
  style_operation renderable (fun node -> map_native_result (Yoga.Node.set_padding node ~edge value))

let set_position renderable ~edge value =
  style_operation renderable (fun node -> map_native_result (Yoga.Node.set_position node ~edge value))

let set_gap renderable ~gutter value =
  style_operation renderable (fun node -> map_native_result (Yoga.Node.set_gap node ~gutter value))

let set_direction renderable value =
  style_operation renderable (fun node -> map_native_result (Yoga.Node.set_direction node value))

let set_flex_direction renderable value =
  style_operation renderable (fun node -> map_native_result (Yoga.Node.set_flex_direction node value))

let set_justify_content renderable value =
  style_operation renderable (fun node -> map_native_result (Yoga.Node.set_justify_content node value))

let set_align_content renderable value =
  style_operation renderable (fun node -> map_native_result (Yoga.Node.set_align_content node value))

let set_align_items renderable value =
  style_operation renderable (fun node -> map_native_result (Yoga.Node.set_align_items node value))

let set_align_self renderable value =
  style_operation renderable (fun node -> map_native_result (Yoga.Node.set_align_self node value))

let set_position_type renderable value =
  style_operation renderable (fun node -> map_native_result (Yoga.Node.set_position_type node value))

let set_wrap renderable value =
  style_operation renderable (fun node -> map_native_result (Yoga.Node.set_wrap node value))

let set_overflow renderable value =
  match style_operation renderable (fun node -> map_native_result (Yoga.Node.set_overflow node value)) with
  | Error error -> Error error
  | Ok () ->
      renderable.overflow <- value;
      bump_render_list_revision renderable;
      Ok ()

let set_display renderable value =
  style_operation renderable (fun node -> map_native_result (Yoga.Node.set_display node value))

let set_box_sizing renderable value =
  style_operation renderable (fun node -> map_native_result (Yoga.Node.set_box_sizing node value))

let set_flex renderable value =
  style_operation renderable (fun node -> map_native_result (Yoga.Node.set_flex node value))

let set_flex_grow renderable value =
  style_operation renderable (fun node -> map_native_result (Yoga.Node.set_flex_grow node value))

let set_flex_shrink renderable value =
  match
    style_operation renderable
      (fun node -> map_native_result (Yoga.Node.set_flex_shrink node value))
  with
  | Error error -> Error error
  | Ok () ->
      renderable.flex_shrink <- Option.value value ~default:1.0;
      Ok ()

let set_aspect_ratio renderable value =
  style_operation renderable (fun node -> map_native_result (Yoga.Node.set_aspect_ratio node value))

let set_border renderable ~edge ~value =
  style_operation renderable (fun node -> map_native_result (Yoga.Node.set_border node ~edge ~value))

let on_focused renderable callback =
  register_event renderable renderable.focused_events Event_kernel.on callback

let once_focused renderable callback =
  register_event renderable renderable.focused_events Event_kernel.once callback

let on_blurred renderable callback =
  register_event renderable renderable.blurred_events Event_kernel.on callback

let once_blurred renderable callback =
  register_event renderable renderable.blurred_events Event_kernel.once callback

let on_destroyed renderable callback =
  register_event renderable renderable.destroyed_events Event_kernel.on callback

let once_destroyed renderable callback =
  register_event renderable renderable.destroyed_events Event_kernel.once callback

let on_resized renderable callback =
  register_event renderable renderable.resized_events Event_kernel.on callback

let once_resized renderable callback =
  register_event renderable renderable.resized_events Event_kernel.once callback

let on_layout_changed renderable callback =
  register_event renderable renderable.layout_changed_events Event_kernel.on callback

let once_layout_changed renderable callback =
  register_event renderable renderable.layout_changed_events Event_kernel.once callback

module Private = struct
  type nonrec rect = rect
  type nonrec behavior = behavior

  let make_behavior = make_behavior
  let default_behavior = default_behavior
  let default_scissor_rect = default_scissor
  let inset_rect = inset_rect

  let create context ?id ?(behavior = default_behavior) () =
    let id =
      Option.value id ~default:(Printf.sprintf "renderable-%d" !next_num)
    in
    create_node context ~id ~behavior ~is_root:false

  let create_root context =
    Result.bind
      (create_node context ~id:"__root__" ~behavior:default_behavior
         ~is_root:true)
      (fun root ->
           match Render_context.width context, Render_context.height context with
           | Ok width, Ok height ->
               (match root.node with
               | None -> Error Error.Destroyed
               | Some node ->
                   (match Yoga.Node.set_width_point node (Int32.to_float width),
                         Yoga.Node.set_height_point node (Int32.to_float height),
                         Yoga.Node.set_flex_direction node Yoga.Flex_column,
                         Yoga.Node.set_flex_shrink node (Some 0.0) with
                   | Ok (), Ok (), Ok (), Ok () ->
                       root.width <- Int32.to_float width;
                       root.height <- Int32.to_float height;
                       root.flex_shrink <- 0.0;
                       invalidate_layout_cache root;
                       Ok root
                   | Error error, _, _, _ | _, Error error, _, _
                   | _, _, Error error, _ | _, _, _, Error error ->
                       destroy root;
                       Error (map_native_error error)))
           | Error error, _ | _, Error error ->
               destroy root;
               Error error)

  let set_behavior = set_behavior
  let with_yoga_node = with_node
  let mark_yoga_dirty = mark_yoga_dirty
  let attach = attach_internal
  let insert_before = insert_before_internal
  let detach = detach_internal
  let find_by_num = find_by_num
  let make_mouse_event = make_mouse_event
  let process_mouse_event = process_mouse_event

  let resize_root root ~width ~height =
    match ensure_open root with
    | Error error -> Error error
    | Ok () when not root.is_root -> Error Error.Invalid_anchor
    | Ok () ->
        (match root.node with
        | None -> Error Error.Destroyed
        | Some node ->
            (match Yoga.Node.set_width_point node (Int32.to_float width),
                  Yoga.Node.set_height_point node (Int32.to_float height) with
            | Ok (), Ok () ->
                invalidate_layout_cache root;
                root.flex_shrink <- 0.0;
                request_render root
                |> Result.map (fun () ->
                       emit root.resized_events root ())
            | Error error, _ | _, Error error -> Error (map_native_error error)))

  let render_root = render_root
end
