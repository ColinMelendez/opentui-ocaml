type t = {
  parent : Renderable.t;
}

let add ?index capability child =
  match index with
  | None ->
      Renderable.Private.attach ~parent:capability.parent ~child
        ~index:(Renderable.child_count capability.parent)
  | Some index ->
      let rec child_at current = function
        | [] -> None
        | child :: rest ->
            if Int.equal current index then Some child
            else child_at (current + 1) rest
      in
      if Int.compare index 0 < 0 then
        Renderable.Private.attach ~parent:capability.parent ~child
          ~index:(Renderable.child_count capability.parent)
      else
        match child_at 0 (Renderable.children capability.parent) with
        | Some anchor ->
            Renderable.Private.insert_before ~parent:capability.parent ~child
              ~anchor
        | None ->
            Renderable.Private.attach ~parent:capability.parent ~child
              ~index:(Renderable.child_count capability.parent)

let insert_before capability child ~anchor =
  Renderable.Private.insert_before ~parent:capability.parent ~child ~anchor

let remove capability child =
  Renderable.Private.detach ~parent:capability.parent ~child

module Private = struct
  let of_renderable parent = { parent }
end
