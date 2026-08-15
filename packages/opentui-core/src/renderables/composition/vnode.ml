type t =
  | Empty
  | Existing of Renderable.t
  | Fragment of t list
  | Element of element
and element = {
  construct : packed_constructor;
  mutable children : t list;
  mutable post_mounts : (Renderable.t -> (unit, Error.t) result) list;
  mutable delegates : (string * string) list;
}

and packed_constructor =
  | Pack : {
      constructor : 'props constructor;
      props : 'props;
    }
    -> packed_constructor

and 'props constructor =
  Render_context.t -> 'props -> (Renderable.t, Error.t) result

type child = t

let empty = Empty
let of_renderable renderable = Existing renderable
let fragment children = Fragment children

let h constructor props children =
  Element
    {
      construct = Pack { constructor; props };
      children;
      post_mounts = [];
      delegates = [];
    }

let add_child node child =
  match node with
  | Element element -> element.children <- element.children @ [ child ]
  | Empty | Existing _ | Fragment _ -> ()

let add_post_mount node callback =
  match node with
  | Element element -> element.post_mounts <- element.post_mounts @ [ callback ]
  | Empty | Existing _ | Fragment _ -> ()

let delegate node mappings =
  match node with
  | Element element -> element.delegates <- mappings @ element.delegates
  | Empty | Existing _ | Fragment _ -> ()

let rec instantiate_many context node =
  match node with
  | Empty -> Ok []
  | Existing renderable -> Ok [ renderable ]
  | Fragment children ->
      let result = ref (Ok []) in
      List.iter
        (fun child ->
          match !result with
          | Error _ -> ()
          | Ok values ->
              (match instantiate_many context child with
              | Error error -> result := Error error
              | Ok mounted -> result := Ok (values @ mounted)))
        children;
      !result
  | Element element ->
      let Pack { constructor; props } = element.construct in
      Result.bind (constructor context props) (fun renderable ->
          let mounted_children = ref [] in
          let child_error = ref None in
          List.iter
            (fun child ->
              match !child_error with
              | Some _ -> ()
              | None ->
                  (match instantiate_many context child with
                  | Error error -> child_error := Some error
                  | Ok mounted ->
                      List.iter
                        (fun child ->
                          if Option.is_none !child_error then
                            match
                              Renderable.Private.attach ~parent:renderable ~child
                                ~index:(Renderable.child_count renderable)
                            with
                            | Ok _ -> mounted_children := child :: !mounted_children
                            | Error error -> child_error := Some error)
                        mounted))
            element.children;
          match !child_error with
          | Some error ->
              Renderable.destroy_recursively renderable;
              Error error
          | None ->
              let post_error = ref None in
              List.iter
                (fun callback ->
                  match !post_error with
                  | Some _ -> ()
                  | None ->
                      (match callback renderable with
                      | Ok () -> ()
                      | Error error -> post_error := Some error))
                element.post_mounts;
              (match !post_error with
              | None -> Ok [ renderable ]
              | Some error ->
                  Renderable.destroy_recursively renderable;
                  Error error))

let instantiate context node = instantiate_many context node

let instantiate_one context node =
  Result.bind (instantiate context node) (function
    | [ renderable ] -> Ok renderable
    | _ -> Error Error.Invalid_argument)

let resolve_delegate root ~name ~id =
  match Renderable.find_descendant_by_id root id with
  | None -> None
  | Some descendant ->
      if String.equal name (Renderable.id descendant) then Some descendant
      else Some descendant
