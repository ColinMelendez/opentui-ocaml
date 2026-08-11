module Native = Opentui_native
module Renderer = Native.Renderer
module Layout = Native.Layout
module Text_renderable = Native.Text_renderable

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

type text_node = {
  renderable : Text_renderable.t;
  foreground : Native.Color.t;
  background : Native.Color.t;
  attributes : int32;
}

type node_kind = Container | Text of text_node

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

let child_count (node : node) = List.length node.children

let create_node parent ~width ~height ~make_kind =
  match ensure_node parent with
  | Error error -> Error error
  | Ok () ->
      (match parent.kind with
      | Text _ -> Error Error.Not_container
      | Container when not (valid_dimension width && valid_dimension height) ->
          Error Error.Invalid_dimensions
      | Container ->
          (match Layout.add_child ~parent:parent.layout with
          | Error error -> Error (Error.Native error)
          | Ok raw_layout ->
              (match Layout.Node.set_dimensions raw_layout ~width ~height with
              | Error error ->
                  (match
                     Layout.remove_child ~parent:parent.layout
                       ~child:raw_layout
                   with
                  | Ok () -> Error (Error.Native error)
                  | Error cleanup_error -> Error (Error.Native cleanup_error))
              | Ok () ->
                  let identity = parent.scene.next_id in
                  parent.scene.next_id <- identity + 1;
                  let node =
                    {
                      scene = parent.scene;
                      identity;
                      layout = raw_layout;
                      kind = make_kind raw_layout;
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
                  Ok node)))

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
      | Container -> Ok ()
      | Text text ->
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
  type t = node

  let id (node : node) = node.identity
  let is_destroyed (node : node) = node.destroyed
  let is_dirty (node : node) = node.dirty
  let children_count (node : node) = child_count node

  let create_container ~parent ~width ~height =
    create_node parent ~width ~height ~make_kind:(fun _ -> Container)

  let create_text ~parent ~width ~height ~text ?(foreground = Native.Color.white)
      ?(background = Native.Color.black) ?(attributes = 0l) () =
    create_node parent ~width ~height
      ~make_kind:(fun raw_layout ->
        Text
          {
            renderable = Text_renderable.create ~node:raw_layout ~text;
            foreground;
            background;
            attributes;
          })

  let set_text node ~text =
    match ensure_node node with
    | Error error -> Error error
    | Ok () ->
        (match node.kind with
        | Container -> Error Error.Not_text
        | Text text_node ->
            Text_renderable.set_text text_node.renderable ~text;
            mark_dirty node;
            Ok ())

  let set_dimensions node ~width ~height =
    match ensure_node node with
    | Error error -> Error error
    | Ok () when not (valid_dimension width && valid_dimension height) ->
        Error Error.Invalid_dimensions
    | Ok () ->
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
                parent.children <-
                  remove_child_by_id node.identity parent.children;
                mark_destroyed node;
                mark_layout_dirty parent;
                Ok ()))
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
                  kind = Container;
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
      | Error error -> Error error
      | Ok () ->
          let written = ref 0l in
          let draw frame =
            match
              Renderer.Frame.clear frame ~background:Native.Color.black
            with
            | Error error -> Error error
            | Ok () ->
                (match scene.root with
                | None -> Error Opentui_native.Error.Closed
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
          | Error error -> Error (Error.Native error)
          | Ok status ->
              let status = render_status status in
              (match status with
              | Rendered | Skipped ->
                  scene.dirty <- false;
                  (match scene.root with
                  | None -> ()
                  | Some root -> mark_clean root)
              | Failed -> ());
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
