type t = {
  text_buffer_renderable : Text_buffer_renderable.t;
  root : Text_node.t;
  children : Text_children.t;
  mutable content : Lib.Styled_text.t;
  mutable manual_content : bool;
}

let as_renderable text =
  Text_buffer_renderable.as_renderable text.text_buffer_renderable

let update_from_nodes text =
  if Text_node.is_dirty text.root && not text.manual_content then
    let content = Text_node.gather text.root in
    match
      Text_buffer_renderable.set_styled_text text.text_buffer_renderable content
    with
    | Error error -> Error error
    | Ok () ->
        text.content <- content;
        Ok ()
  else Ok ()

let create context ?id ?width_method ?wrap_mode ?content () =
  match
    Text_buffer_renderable.create context ?id ?width_method ?wrap_mode ()
  with
  | Error error -> Error error
  | Ok text_buffer_renderable ->
      let manual_content = Option.is_some content in
      let content = Option.value content ~default:(Lib.Styled_text.of_string "") in
      (match
         Text_buffer_renderable.set_styled_text text_buffer_renderable content
       with
      | Error error ->
          Text_buffer_renderable.destroy text_buffer_renderable;
          Error error
      | Ok () ->
          let text_ref : t option ref = ref None in
          let root_id =
            match id with
            | None -> None
            | Some id -> Some (id ^ "-root")
          in
          let root_request () =
            Option.iter
              (fun text -> ignore (Renderable.request_render (as_renderable text)))
              !text_ref
          in
          let root =
            Text_node.Private.create_root ?id:root_id ~on_change:root_request ()
          in
          let text =
            {
              text_buffer_renderable;
              root;
              children = Text_children.Private.of_node root;
              content;
              manual_content;
            }
          in
          text_ref := Some text;
          Text_buffer_renderable.Private.set_lifecycle_pass
            text_buffer_renderable
            (Some (fun () -> ignore (update_from_nodes text)));
          Ok text)

let text_node text = text.root
let children text = text.children
let get_text_children text = Text_children.children text.children
let content text = text.content

let selected_text text =
  Text_buffer_renderable.selected_text text.text_buffer_renderable

let set_content text content =
  match
    Text_buffer_renderable.set_styled_text text.text_buffer_renderable content
  with
  | Error error -> Error error
  | Ok () ->
      text.content <- content;
      text.manual_content <- true;
      Ok ()

let add ?index text child = Text_children.add ?index text.children child
let remove text child = Text_children.remove text.children child

let insert_before text child ~anchor =
  Text_children.insert_before text.children child ~anchor

let clear text =
  Text_node.clear text.root;
  let content = Lib.Styled_text.of_string "" in
  match Text_buffer_renderable.clear text.text_buffer_renderable with
  | Error error -> Error error
  | Ok () ->
      text.content <- content;
      Ok ()

let destroy text =
  Text_node.Private.discard_children text.root;
  Text_buffer_renderable.destroy text.text_buffer_renderable
