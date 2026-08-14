type style = {
  fg : Color.t option;
  bg : Color.t option;
  attributes : int;
  link : string option;
}

type child =
  | Text_string of string
  | Text_node of t

and input =
  | String of string
  | Node of t
  | Styled of Lib.Styled_text.t

and t = {
  id : string;
  mutable parent : t option;
  mutable children : child list;
  mutable dirty : bool;
  mutable fg : Color.t option;
  mutable bg : Color.t option;
  mutable attributes : int;
  mutable link : string option;
  root_request : (unit -> unit) option;
  is_root : bool;
}

let next_id = ref 1

let fresh_id () =
  let value = !next_id in
  incr next_id;
  Printf.sprintf "text-node-%d" value

let create ?id ?fg ?bg ?(attributes = 0) ?link () =
  {
    id = Option.value id ~default:(fresh_id ());
    parent = None;
    children = [];
    dirty = false;
    fg;
    bg;
    attributes;
    link;
    root_request = None;
    is_root = false;
  }

let create_root ?(id = "text-root") ~on_change () =
  {
    id;
    parent = None;
    children = [];
    dirty = false;
    fg = None;
    bg = None;
    attributes = 0;
    link = None;
    root_request = Some on_change;
    is_root = true;
  }

let id node = node.id
let parent node = node.parent
let children node = node.children
let child_count node = List.length node.children

let get_children node =
  List.filter_map
    (function Text_string _ -> None | Text_node child -> Some child)
    node.children

let find_child_by_id node id =
  let rec find = function
    | [] -> None
    | Text_string _ :: rest -> find rest
    | Text_node child :: rest ->
        if String.equal child.id id then Some child else find rest
  in
  find node.children

let is_dirty node = node.dirty

let rec request_render node =
  node.dirty <- true;
  match node.parent with
  | Some parent -> request_render parent
  | None when node.is_root -> Option.iter (fun request -> request ()) node.root_request
  | None -> ()

let is_ancestor candidate node =
  let rec loop current =
    match current.parent with
    | None -> false
    | Some parent -> parent == candidate || loop parent
  in
  loop node

let splice_index length index =
  if Int.compare index 0 >= 0 then min index length
  else max 0 (length + index)

let clamp_index length index = max 0 (min index length)

let remove_node_without_request parent child =
  let rec remove_first prefix = function
    | [] -> None
    | Text_string text :: rest ->
        remove_first (Text_string text :: prefix) rest
    | Text_node candidate :: rest when candidate == child ->
        Some (List.rev_append prefix rest)
    | current :: rest -> remove_first (current :: prefix) rest
  in
  match remove_first [] parent.children with
  | None -> Error Error.Not_child
  | Some children ->
      parent.children <- children;
      child.parent <- None;
      Ok ()

let rec prepare_node_insert parent child index =
  if child == parent || is_ancestor child parent then Error Error.Invalid_anchor
  else
    let old_length = List.length parent.children in
    let insert_index = Option.value index ~default:old_length in
    match child.parent with
    | None -> Ok (clamp_index (List.length parent.children) insert_index)
    | Some old_parent when old_parent == parent ->
        let rec find_index current = function
          | [] -> None
          | Text_string _ :: rest -> find_index (current + 1) rest
          | Text_node candidate :: rest ->
              if candidate == child then Some current
              else find_index (current + 1) rest
        in
        (match find_index 0 parent.children with
        | None -> Error Error.Not_child
        | Some current_index ->
            (match remove_node_without_request parent child with
            | Error error -> Error error
            | Ok () ->
                let adjusted_index =
                  if current_index < insert_index then insert_index - 1
                  else insert_index
                in
                Ok
                  (clamp_index (List.length parent.children) adjusted_index)))
    | Some old_parent ->
        (match remove old_parent child with
        | Error error -> Error error
        | Ok () -> Ok (clamp_index (List.length parent.children) insert_index))

and remove parent child =
  match remove_node_without_request parent child with
  | Error error -> Error error
  | Ok () ->
      request_render parent;
      Ok ()

let add_string parent text index =
  let insert_index =
    match index with
    | None -> List.length parent.children
    | Some index -> splice_index (List.length parent.children) index
  in
  let rec insert_at current = function
    | [] when Int.equal current insert_index -> [ Text_string text ]
    | [] -> [ Text_string text ]
    | child :: rest when Int.equal current insert_index ->
        Text_string text :: child :: rest
    | child :: rest -> child :: insert_at (current + 1) rest
  in
  parent.children <- insert_at 0 parent.children;
  request_render parent;
  match index with Some index -> Ok index | None -> Ok insert_index

let add_styled parent styled index =
  let nodes =
    List.map
      (fun (chunk : Lib.Styled_text.chunk) ->
        let node =
          create ?fg:chunk.fg ?bg:chunk.bg ~attributes:chunk.attributes
            ?link:chunk.link ()
        in
        ignore (add_string node chunk.text None);
        node)
      (Lib.Styled_text.chunks styled)
  in
  let insert_index =
    match index with
    | None -> List.length parent.children
    | Some index -> splice_index (List.length parent.children) index
  in
  let rec split_at current = function
    | [] -> [], []
    | child :: rest when Int.equal current insert_index -> [], child :: rest
    | child :: rest ->
        let left, right = split_at (current + 1) rest in
        child :: left, right
  in
  let left, right = split_at 0 parent.children in
  parent.children <-
    left @ List.concat_map (fun node -> [ Text_node node ]) nodes @ right;
  List.iter (fun node -> node.parent <- Some parent) nodes;
  request_render parent;
  match index with Some index -> Ok index | None -> Ok insert_index

let add ?index parent input =
  match input with
  | String text -> add_string parent text index
  | Styled styled -> add_styled parent styled index
  | Node child ->
      (match prepare_node_insert parent child index with
      | Error error -> Error error
      | Ok insert_index ->
          let rec insert_at current = function
            | [] -> [ Text_node child ]
            | item :: rest when Int.equal current insert_index ->
                Text_node child :: item :: rest
            | item :: rest -> item :: insert_at (current + 1) rest
          in
          parent.children <- insert_at 0 parent.children;
          child.parent <- Some parent;
          request_render parent;
          Ok insert_index)

let insert_before parent input ~anchor =
  let rec find index = function
    | [] -> None
    | Text_string _ :: rest -> find (index + 1) rest
    | Text_node child :: _ when child == anchor -> Some index
    | _ :: rest -> find (index + 1) rest
  in
  match find 0 parent.children with
  | None -> Error Error.Invalid_anchor
  | Some index ->
      if match input with Node child -> child == anchor | String _ | Styled _ -> false
      then Ok ()
      else
        match add ~index parent input with
        | Error error -> Error error
        | Ok _ -> Ok ()

let clear node =
  List.iter
    (function Text_string _ -> () | Text_node child -> child.parent <- None)
    node.children;
  node.children <- [];
  request_render node

let default_style = { fg = None; bg = None; attributes = 0; link = None }

let merge_style (node : t) (inherited : style) =
  let first_some value fallback =
    match value with Some _ -> value | None -> fallback
  in
  {
    fg = first_some node.fg inherited.fg;
    bg = first_some node.bg inherited.bg;
    attributes = node.attributes lor inherited.attributes;
    link = first_some node.link inherited.link;
  }

let rec gather ?(inherited = default_style) (node : t) =
  let style = merge_style node inherited in
  let chunks =
    List.concat_map
      (function
        | Text_string text ->
            [ Lib.Styled_text.chunk ?fg:style.fg ?bg:style.bg
                ~attributes:style.attributes ?link:style.link text ]
        | Text_node child ->
            Lib.Styled_text.chunks (gather ~inherited:style child))
      node.children
  in
  node.dirty <- false;
  Lib.Styled_text.create chunks

let fg node = node.fg
let set_fg node value = node.fg <- value; request_render node
let bg node = node.bg
let set_bg node value = node.bg <- value; request_render node
let attributes node = node.attributes
let set_attributes node value = node.attributes <- value; request_render node
let link node = node.link
let set_link node value = node.link <- value; request_render node

module Private = struct
  let create_root = create_root

  let discard_children node =
    node.children <- []
end
