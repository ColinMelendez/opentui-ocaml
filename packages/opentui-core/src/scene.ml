module Core_renderer = Renderer
module Renderer = Core_renderer
module Text_renderable = Renderables.Text
module Box_renderable = Renderables.Box

(* Scene is retained only as the current low-level test surface until the
   renderer/renderable port replaces it. Its layout owner is private and uses
   the independent Yoga-node seam; the public Yoga module no longer exposes a
   tree owner. *)
module Layout = struct
  type direction = Yoga.direction = Inherit | Ltr | Rtl

  type layout = Yoga.layout = {
    left : float;
    top : float;
    right : float;
    bottom : float;
    width : float;
    height : float;
  }

  type t = {
    root : Yoga.Node.t;
    mutable closed : bool;
  }

  module Node = struct
    type t = Yoga.Node.t
    type edge = Yoga.edge = Left | Top | Right | Bottom | Start | End | Horizontal | Vertical | All

    let max_dimension = 3.4028234663852886e38

    let valid_dimension value =
      match classify_float value with
      | FP_nan | FP_infinite -> false
      | FP_zero | FP_subnormal | FP_normal ->
          Float.compare value 0.0 >= 0
          && Float.compare value max_dimension <= 0

    let set_dimensions node ~width ~height =
      if not (valid_dimension width && valid_dimension height) then
        Error (Native.Error.Native Opentui_raw.Error.Invalid_argument)
      else
        match Yoga.Node.set_width_point node width with
        | Error error -> Error error
        | Ok () -> Yoga.Node.set_height_point node height

    let set_padding node ~edge ~value =
      Yoga.Node.set_padding_point node ~edge ~value

    let set_border node ~edge ~value =
      Yoga.Node.set_border node ~edge ~value:(Some value)

    let layout = Yoga.Node.layout
  end

  let create () =
    match Yoga.Node.create () with
    | Error error -> Error error
    | Ok root -> Ok { root; closed = false }

  let close layout =
    if not layout.closed then begin
      layout.closed <- true;
      ignore (Yoga.Node.free_recursive layout.root)
    end

  let root layout = if layout.closed then Error Native.Error.Closed else Ok layout.root

  let add_child ~parent =
    match Yoga.Node.child_count parent with
    | Error error -> Error error
    | Ok count ->
        (match Yoga.Node.create () with
        | Error error -> Error error
        | Ok child ->
            (match Yoga.Node.insert_child ~parent ~child ~index:count with
            | Ok () -> Ok child
            | Error error ->
                (match Yoga.Node.free child with
                | Ok () -> Error error
                | Error cleanup_error -> Error cleanup_error)))

  let remove_child ~parent ~child = Yoga.Node.remove_child ~parent ~child
  let move_child ~parent ~child ~index = Yoga.Node.move_child ~parent ~child ~index

  let calculate layout ~width ~height ~direction =
    Yoga.Node.calculate_layout layout.root ~width ~height ~direction
end

type border_style = Box_renderable.border_style =
  | No_border
  | Single
  | Double
  | Rounded
  | Heavy

type pointer_kind = Down | Up | Move | Drag | Scroll

type pointer_event = {
  kind : pointer_kind;
  button : int;
  x : int;
  y : int;
}

type propagation = Continue | Stop

type render_status = Rendered | Skipped | Failed

type flush_result = {
  status : render_status;
  bytes_written : int32;
}

type bounds = {
  left : float;
  top : float;
  width : float;
  height : float;
}

type box_node = {
  renderable : Box_renderable.t;
}

type text_node = {
  renderable : Text_renderable.t;
  mutable foreground : Color.t;
  mutable background : Color.t;
  mutable attributes : int32;
}

type node_kind = Box_node of box_node | Text_node of text_node

type scene = {
  renderer : Renderer.t;
  layout : Layout.t;
  mutable width : int32;
  mutable height : int32;
  mutable closed : bool;
  mutable dirty : bool;
  mutable layout_dirty : bool;
  mutable next_id : int;
  mutable root : node option;
}

and node = {
  scene : scene;
  identity : int;
  layout : Layout.Node.t;
  kind : node_kind;
  mutable parent : node option;
  mutable children : node list;
  mutable dirty : bool;
  mutable destroyed : bool;
  mutable pointer_handler : pointer_handler option;
  mutable bounds : bounds;
}

and pointer_handler = node -> pointer_event -> propagation

type box = { box_node : node }
type text = { text_node : node }

type t = scene
type error = Error.t
type dispatch_result = Unhandled | Handled of node

let max_dimension = 3.4028234663852886e38

let valid_dimension value =
  match classify_float value with
  | FP_nan | FP_infinite -> false
  | FP_zero | FP_subnormal | FP_normal ->
      Float.compare value 0.0 >= 0
      && Float.compare value max_dimension <= 0

let finite value =
  match classify_float value with
  | FP_nan | FP_infinite -> false
  | FP_zero | FP_subnormal | FP_normal -> true

let valid_layout layout =
  finite layout.Layout.left
  && finite layout.Layout.top
  && finite layout.Layout.right
  && finite layout.Layout.bottom
  && finite layout.Layout.width
  && finite layout.Layout.height
  && Float.compare layout.Layout.width 0.0 >= 0
  && Float.compare layout.Layout.height 0.0 >= 0

let ensure_scene scene =
  if scene.closed then Error Error.Closed else Ok ()

let ensure_node (node : node) =
  if node.scene.closed then Error Error.Closed
  else if node.destroyed then Error Error.Destroyed
  else Ok ()

let ensure_box_node (node : node) =
  match ensure_node node with
  | Error error -> Error error
  | Ok () ->
      (match node.kind with
      | Box_node box -> Ok box
      | Text_node _ -> Error Error.Not_box)

let color_equal left right =
  let left_red, left_green, left_blue, left_alpha =
    Color.channels left
  in
  let right_red, right_green, right_blue, right_alpha =
    Color.channels right
  in
  Int.equal left_red right_red
  && Int.equal left_green right_green
  && Int.equal left_blue right_blue
  && Int.equal left_alpha right_alpha

let border_equal left right =
  match left, right with
  | No_border, No_border
  | Single, Single
  | Double, Double
  | Rounded, Rounded
  | Heavy, Heavy -> true
  | No_border, (Single | Double | Rounded | Heavy)
  | Single, (No_border | Double | Rounded | Heavy)
  | Double, (No_border | Single | Rounded | Heavy)
  | Rounded, (No_border | Single | Double | Heavy)
  | Heavy, (No_border | Single | Double | Rounded) -> false

let border_inset border =
  match border with No_border -> 0.0 | Single | Double | Rounded | Heavy -> 1.0

let set_box_border layout ~border =
  let value = border_inset border in
  let set edge =
    match Layout.Node.set_border layout ~edge ~value with
    | Ok () -> Ok ()
    | Error error -> Error (Error.Native error)
  in
  match set Layout.Node.Left with
  | Error error -> Error error
  | Ok () ->
      (match set Layout.Node.Right with
      | Error error -> Error error
      | Ok () ->
          (match set Layout.Node.Top with
          | Error error -> Error error
          | Ok () -> set Layout.Node.Bottom))

let mark_dirty (node : node) =
  node.dirty <- true;
  node.scene.dirty <- true

let mark_layout_dirty (node : node) =
  mark_dirty node;
  node.scene.layout_dirty <- true

let rec mark_clean (node : node) =
  if not node.destroyed then begin
    node.dirty <- false;
    let rec clean_children = function
      | [] -> ()
      | child :: rest ->
          mark_clean child;
          clean_children rest
    in
    clean_children node.children
  end

let rec mark_destroyed (node : node) =
  node.destroyed <- true;
  node.dirty <- false;
  node.pointer_handler <- None;
  node.parent <- None;
  let children = node.children in
  node.children <- [];
  let rec destroy_children = function
    | [] -> ()
    | child :: rest ->
        mark_destroyed child;
        destroy_children rest
  in
  destroy_children children

let remove_child_by_id identity children =
  let rec remove = function
    | [] -> []
    | child :: rest when Int.equal child.identity identity -> rest
    | child :: rest -> child :: remove rest
  in
  remove children

let move_child_to_index identity index children =
  let ordered = List.rev children in
  let rec detach position reverse_prefix = function
    | [] -> None
    | child :: rest when Int.equal child.identity identity ->
        Some (position, child, List.rev_append reverse_prefix rest)
    | child :: rest -> detach (position + 1) (child :: reverse_prefix) rest
  in
  match detach 0 [] ordered with
  | None -> None
  | Some (current_index, child, remaining) ->
      let reordered =
        if Int.equal current_index index then ordered
        else
          let rec insert_node remaining reverse_prefix = function
            | rest when Int.equal remaining 0 ->
                List.rev_append reverse_prefix (child :: rest)
            | child :: rest ->
                insert_node (remaining - 1) (child :: reverse_prefix) rest
            | [] -> List.rev_append reverse_prefix []
          in
          insert_node index [] remaining
      in
      Some (current_index, List.rev reordered)

let child_count (node : node) = List.length node.children

let create_node parent ~width ~height ~make_kind =
  match ensure_node parent with
  | Error error -> Error error
  | Ok () ->
      (match parent.kind with
      | Text_node _ -> Error Error.Not_container
      | Box_node _ when not (valid_dimension width && valid_dimension height) ->
          Error Error.Invalid_dimensions
      | Box_node _ ->
          (match Layout.add_child ~parent:parent.layout with
          | Error error -> Error (Error.Native error)
          | Ok raw_layout ->
              (match Layout.Node.set_dimensions raw_layout ~width ~height with
              | Error error ->
                  (match
                     Layout.remove_child ~parent:parent.layout
                       ~child:raw_layout
                   with
                  | Ok () ->
                      (match Yoga.Node.free_recursive raw_layout with
                      | Ok () -> Error (Error.Native error)
                      | Error cleanup_error ->
                          Error (Error.Native cleanup_error))
                  | Error cleanup_error -> Error (Error.Native cleanup_error))
              | Ok () ->
                  (match make_kind raw_layout with
                  | Error error ->
                      (match
                         Layout.remove_child ~parent:parent.layout
                           ~child:raw_layout
                       with
                      | Ok () ->
                          (match Yoga.Node.free_recursive raw_layout with
                          | Ok () -> Error error
                          | Error cleanup_error ->
                              Error (Error.Native cleanup_error))
                      | Error cleanup_error ->
                          Error (Error.Native cleanup_error))
                  | Ok kind ->
                      let identity = parent.scene.next_id in
                      parent.scene.next_id <- identity + 1;
                      let node =
                        {
                          scene = parent.scene;
                          identity;
                          layout = raw_layout;
                          kind;
                          parent = Some parent;
                          children = [];
                          dirty = true;
                          destroyed = false;
                          pointer_handler = None;
                          bounds = { left = 0.0; top = 0.0; width; height };
                        }
                      in
                      parent.children <- node :: parent.children;
                      mark_layout_dirty parent;
                      Ok node))))

let rec update_bounds (node : node) parent_left parent_top =
  if node.destroyed then Ok ()
  else
    match Layout.Node.layout node.layout with
    | Error error -> Error (Error.Native error)
    | Ok layout when not (valid_layout layout) -> Error Error.Invalid_layout
    | Ok layout ->
        let bounds =
          {
            left = parent_left +. layout.Layout.left;
            top = parent_top +. layout.Layout.top;
            width = layout.Layout.width;
            height = layout.Layout.height;
          }
        in
        node.bounds <- bounds;
        let rec update_children = function
          | [] -> Ok ()
          | child :: rest ->
              (match update_bounds child bounds.left bounds.top with
              | Error error -> Error error
              | Ok () -> update_children rest)
        in
        update_children node.children

let ensure_layout scene =
  if not scene.layout_dirty then Ok ()
  else
    match
      Layout.calculate scene.layout ~width:(Int32.to_float scene.width)
        ~height:(Int32.to_float scene.height) ~direction:Layout.Ltr
    with
    | Error error -> Error (Error.Native error)
    | Ok () ->
        (match scene.root with
        | None -> Error Error.Closed
        | Some root ->
            (match update_bounds root 0.0 0.0 with
            | Error error -> Error error
            | Ok () ->
                scene.layout_dirty <- false;
                Ok ()))

let rec draw_node frame (node : node) parent_left parent_top =
  if node.destroyed then Ok ()
  else
    let draw_self () =
      match node.kind with
      | Box_node box ->
          Box_renderable.draw box.renderable frame ~offset_x:parent_left
            ~offset_y:parent_top
      | Text_node text ->
          Text_renderable.draw text.renderable frame ~offset_x:parent_left
            ~offset_y:parent_top
            ~foreground:text.foreground ~background:text.background
            ~attributes:text.attributes
    in
    match draw_self () with
    | Error error -> Error error
    | Ok () ->
        let rec draw_children = function
          | [] -> Ok ()
          | child :: rest ->
              (match draw_children rest with
              | Error error -> Error error
              | Ok () ->
                  draw_node frame child node.bounds.left node.bounds.top)
        in
        draw_children node.children

let render_status status =
  match status with
  | Renderer.Rendered -> Rendered
  | Renderer.Skipped -> Skipped
  | Renderer.Failed -> Failed

let rec hit_test (node : node) event =
  if node.destroyed then None
  else
    let x = Int.to_float event.x in
    let y = Int.to_float event.y in
    let within value start length =
      Float.compare value start >= 0
      && Float.compare value (start +. length) < 0
    in
    if not
        (within x node.bounds.left node.bounds.width
        && within y node.bounds.top node.bounds.height)
    then None
    else
      let rec find_child = function
        | [] -> Some node
        | child :: rest ->
            (match hit_test child event with
            | Some target -> Some target
            | None -> find_child rest)
      in
      find_child node.children

let dispatch_handlers (target : node) event =
  let rec visit node =
    let parent = node.parent in
    match node.pointer_handler with
    | None ->
        (match parent with
        | None -> false
        | Some parent_node -> visit parent_node)
    | Some handler ->
        (match handler node event with
        | Stop -> true
        | Continue ->
            (match parent with
            | None -> true
            | Some parent_node ->
                ignore (visit parent_node);
                true))
  in
  visit target

module Node = struct
  type kind = Box | Text
  type t = node

  let id (node : node) = node.identity
  let is_destroyed (node : node) = node.destroyed
  let is_dirty (node : node) = node.dirty
  let children_count (node : node) = child_count node

  let kind (node : node) =
    match node.kind with Box_node _ -> Box | Text_node _ -> Text

  let move_to_index node ~index =
    match ensure_node node with
    | Error error -> Error error
    | Ok () when Int.equal node.identity 0 -> Error Error.Cannot_move_root
    | Ok () ->
        (match node.parent with
        | None -> Error Error.Cannot_move_root
        | Some parent ->
            let count = child_count parent in
            if Int.compare index 0 < 0 || Int.compare index count >= 0 then
              Error Error.Invalid_child_index
            else
              (match move_child_to_index node.identity index parent.children with
              | None -> Error Error.Invalid_child_index
              | Some (current_index, reordered) when
                  Int.equal current_index index -> Ok ()
              | Some (_, reordered) ->
                  (match
                     Layout.move_child ~parent:parent.layout ~child:node.layout
                       ~index:(Int32.of_int index)
                   with
                  | Error error -> Error (Error.Native error)
                  | Ok () ->
                      parent.children <- reordered;
                      mark_layout_dirty parent;
                      Ok ())))

  let create_box ~parent ~width ~height ?(background = Color.black)
      ?(border = No_border) ?(border_color = Color.white)
      ?(should_fill = false) () =
    create_node parent ~width ~height
      ~make_kind:(fun raw_layout ->
        match set_box_border raw_layout ~border with
        | Error error -> Error error
        | Ok () ->
            Ok
              (Box_node
                 {
                   renderable =
                     Box_renderable.create ~node:raw_layout ~background ~border
                       ~border_color ~should_fill ();
                 }))

  let create_text ~parent ~width ~height ~text ?(foreground = Color.white)
      ?(background = Color.black) ?(attributes = 0l) () =
    create_node parent ~width ~height
      ~make_kind:(fun raw_layout ->
        Ok
          (Text_node
             {
               renderable = Text_renderable.create ~node:raw_layout ~text;
               foreground;
               background;
               attributes;
             }))

  let set_text node ~text =
    match ensure_node node with
    | Error error -> Error error
    | Ok () ->
        (match node.kind with
        | Box_node _ -> Error Error.Not_text
        | Text_node text_node ->
            if String.equal (Text_renderable.text text_node.renderable) text
            then Ok ()
            else begin
              Text_renderable.set_text text_node.renderable ~text;
              mark_dirty node;
              Ok ()
            end)

  let set_text_foreground node ~foreground =
    match ensure_node node with
    | Error error -> Error error
    | Ok () ->
        (match node.kind with
        | Box_node _ -> Error Error.Not_text
        | Text_node text_node ->
            if color_equal text_node.foreground foreground then Ok ()
            else begin
              text_node.foreground <- foreground;
              mark_dirty node;
              Ok ()
            end)

  let set_text_background node ~background =
    match ensure_node node with
    | Error error -> Error error
    | Ok () ->
        (match node.kind with
        | Box_node _ -> Error Error.Not_text
        | Text_node text_node ->
            if color_equal text_node.background background then Ok ()
            else begin
              text_node.background <- background;
              mark_dirty node;
              Ok ()
            end)

  let set_text_attributes node ~attributes =
    match ensure_node node with
    | Error error -> Error error
    | Ok () ->
        (match node.kind with
        | Box_node _ -> Error Error.Not_text
        | Text_node text_node ->
            if Int.equal (Int32.compare text_node.attributes attributes) 0
            then Ok ()
            else begin
              text_node.attributes <- attributes;
              mark_dirty node;
              Ok ()
            end)

  let set_dimensions node ~width ~height =
    match ensure_node node with
    | Error error -> Error error
    | Ok () when not (valid_dimension width && valid_dimension height) ->
        Error Error.Invalid_dimensions
    | Ok () ->
        if
          Int.equal (Float.compare node.bounds.width width) 0
          && Int.equal (Float.compare node.bounds.height height) 0
        then Ok ()
        else
          (match Layout.Node.set_dimensions node.layout ~width ~height with
          | Error error -> Error (Error.Native error)
          | Ok () ->
              node.bounds <- { node.bounds with width; height };
              mark_layout_dirty node;
              Ok ())

  let set_pointer_handler node handler =
    match ensure_node node with
    | Error error -> Error error
    | Ok () ->
        node.pointer_handler <- Some handler;
        Ok ()

  let clear_pointer_handler node =
    match ensure_node node with
    | Error error -> Error error
    | Ok () ->
        node.pointer_handler <- None;
        Ok ()

  let destroy node =
    match ensure_node node with
    | Error error -> Error error
    | Ok () when Int.equal node.identity 0 ->
        Error Error.Cannot_destroy_root
    | Ok () ->
        (match node.parent with
        | None -> Error Error.Cannot_destroy_root
        | Some parent ->
            (match
               Layout.remove_child ~parent:parent.layout ~child:node.layout
             with
            | Error error -> Error (Error.Native error)
            | Ok () ->
                (match Yoga.Node.free_recursive node.layout with
                | Error error -> Error (Error.Native error)
                | Ok () ->
                    parent.children <-
                      remove_child_by_id node.identity parent.children;
                    mark_destroyed node;
                    mark_layout_dirty parent;
                    Ok ())))
end

module Box = struct
  type t = box

  let create ~parent ~width ~height ?background ?border ?border_color
      ?should_fill () =
    match
      Node.create_box ~parent ~width ~height ?background ?border ?border_color
        ?should_fill ()
    with
    | Error error -> Error error
    | Ok node -> Ok { box_node = node }

  let node box = box.box_node

  let renderable box =
    match box.box_node.kind with
    | Box_node box_node -> box_node.renderable
    | Text_node _ -> assert false

  let background box = Box_renderable.background (renderable box)

  let set_background box ~background =
    match ensure_box_node box.box_node with
    | Error error -> Error error
    | Ok box_node ->
        if color_equal (Box_renderable.background box_node.renderable) background
        then Ok ()
        else begin
          Box_renderable.set_background box_node.renderable ~background;
          mark_dirty box.box_node;
          Ok ()
        end

  let border box = Box_renderable.border (renderable box)

  let set_border box ~border =
    match ensure_box_node box.box_node with
    | Error error -> Error error
    | Ok box_node ->
        let renderable = box_node.renderable in
        let current = Box_renderable.border renderable in
        if border_equal current border then Ok ()
        else
          let current_inset = border_inset current in
          let next_inset = border_inset border in
          let border_result =
            if Int.equal (Float.compare current_inset next_inset) 0 then Ok ()
            else set_box_border box.box_node.layout ~border
          in
          (match border_result with
          | Error error -> Error error
          | Ok () ->
              Box_renderable.set_border renderable ~border;
              if Int.equal (Float.compare current_inset next_inset) 0 then
                mark_dirty box.box_node
              else mark_layout_dirty box.box_node;
              Ok ())

  let border_color box = Box_renderable.border_color (renderable box)

  let set_border_color box ~border_color =
    match ensure_box_node box.box_node with
    | Error error -> Error error
    | Ok box_node ->
        if color_equal
             (Box_renderable.border_color box_node.renderable)
             border_color
        then Ok ()
        else begin
          Box_renderable.set_border_color box_node.renderable ~border_color;
          mark_dirty box.box_node;
          Ok ()
        end

  let should_fill box = Box_renderable.should_fill (renderable box)

  let set_should_fill box ~should_fill =
    match ensure_box_node box.box_node with
    | Error error -> Error error
    | Ok box_node ->
        if Bool.equal
             (Box_renderable.should_fill box_node.renderable)
             should_fill
        then Ok ()
        else begin
          Box_renderable.set_should_fill box_node.renderable ~should_fill;
          mark_dirty box.box_node;
          Ok ()
        end
end

module Text = struct
  type t = text

  let create ~parent ~width ~height ~text ?foreground ?background ?attributes () =
    match
      Node.create_text ~parent ~width ~height ~text ?foreground ?background
        ?attributes ()
    with
    | Error error -> Error error
    | Ok node -> Ok { text_node = node }

  let node text = text.text_node

  let renderable text =
    match text.text_node.kind with
    | Box_node _ -> assert false
    | Text_node text_node -> text_node.renderable

  let content text = Text_renderable.text (renderable text)
  let set text ~content = Node.set_text text.text_node ~text:content

  let foreground text =
    match text.text_node.kind with
    | Box_node _ -> assert false
    | Text_node text_node -> text_node.foreground

  let background text =
    match text.text_node.kind with
    | Box_node _ -> assert false
    | Text_node text_node -> text_node.background

  let attributes text =
    match text.text_node.kind with
    | Box_node _ -> assert false
    | Text_node text_node -> text_node.attributes

  let set_foreground text ~foreground =
    Node.set_text_foreground text.text_node ~foreground

  let set_background text ~background =
    Node.set_text_background text.text_node ~background

  let set_attributes text ~attributes =
    Node.set_text_attributes text.text_node ~attributes
end

let create ~width ~height =
  match Renderer.create ~width ~height with
  | Error error -> Error (Error.Native error)
  | Ok renderer ->
      (match Layout.create () with
      | Error error ->
          Renderer.close renderer;
          Error (Error.Native error)
      | Ok layout ->
          (match Layout.root layout with
          | Error error ->
              Layout.close layout;
              Renderer.close renderer;
              Error (Error.Native error)
          | Ok raw_root ->
              let scene =
                {
                  renderer;
                  layout;
                  width;
                  height;
                  closed = false;
                  dirty = true;
                  layout_dirty = true;
                  next_id = 1;
                  root = None;
                }
              in
              let root =
                {
                  scene;
                  identity = 0;
                  layout = raw_root;
                  kind =
                    Box_node
                      {
                        renderable = Box_renderable.create ~node:raw_root ();
                      };
                  parent = None;
                  children = [];
                  dirty = true;
                  destroyed = false;
                  pointer_handler = None;
                  bounds =
                    {
                      left = 0.0;
                      top = 0.0;
                      width = Int32.to_float width;
                      height = Int32.to_float height;
                    };
                }
              in
              scene.root <- Some root;
              Ok scene))

let root scene =
  match ensure_scene scene with
  | Error error -> Error error
  | Ok () ->
      (match scene.root with Some root -> Ok root | None -> Error Error.Closed)

let resize scene ~width ~height =
  match ensure_scene scene with
  | Error error -> Error error
  | Ok () ->
      (match Renderer.resize scene.renderer ~width ~height with
      | Error error -> Error (Error.Native error)
      | Ok () ->
          scene.width <- width;
          scene.height <- height;
          scene.layout_dirty <- true;
          scene.dirty <- true;
          Ok ())

let flush scene ~force ~output =
  match ensure_scene scene with
  | Error error -> Error error
  | Ok () when not scene.dirty && not force ->
      Ok { status = Skipped; bytes_written = 0l }
  | Ok () ->
      (match ensure_layout scene with
      | Error error ->
          scene.dirty <- true;
          Error error
      | Ok () ->
          let written = ref 0l in
          let draw frame =
            match
              Renderer.Frame.clear frame ~background:Color.black
            with
            | Error error -> Error error
            | Ok () ->
                (match scene.root with
                | None -> Error Native.Error.Closed
                | Some root ->
                    (match draw_node frame root 0.0 0.0 with
                    | Error error -> Error error
                    | Ok () ->
                        (match
                           Renderer.Frame.write_resolved_chars frame ~output
                             ~add_line_breaks:false
                         with
                        | Error error -> Error error
                        | Ok count ->
                            written := count;
                            Ok ())))
          in
          (match Renderer.run_frame scene.renderer ~force ~draw with
          | Error error ->
              scene.dirty <- true;
              Error (Error.Native error)
          | Ok status ->
              let status = render_status status in
              (match status with
              | Rendered | Skipped ->
                  scene.dirty <- false;
                  (match scene.root with
                  | None -> ()
                  | Some root -> mark_clean root)
              | Failed -> scene.dirty <- true);
              let bytes_written =
                match status with Rendered -> !written | Skipped | Failed -> 0l
              in
              Ok { status; bytes_written }))

let dispatch_pointer scene event =
  match ensure_scene scene with
  | Error error -> Error error
  | Ok () ->
      (match ensure_layout scene with
      | Error error -> Error error
      | Ok () ->
          (match scene.root with
          | None -> Error Error.Closed
          | Some root ->
              (match hit_test root event with
              | None -> Ok Unhandled
              | Some target ->
                  if dispatch_handlers target event then Ok (Handled target)
                  else Ok Unhandled)))

let close scene =
  if not scene.closed then begin
    scene.closed <- true;
    (match scene.root with
    | None -> ()
    | Some root -> mark_destroyed root);
    Renderer.close scene.renderer;
    Layout.close scene.layout
  end
