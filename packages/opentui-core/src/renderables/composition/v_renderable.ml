type render =
  Buffer.t -> delta_time:float -> renderable:Renderable.t -> (unit, Error.t) result

type t = {
  renderable : Renderable.t;
  children : Layout_children.t;
  mutable render : render option;
}

let draw value renderable buffer delta_time =
  match value.render with
  | None -> Ok ()
  | Some callback -> callback buffer ~delta_time ~renderable

let create context ?id ?width ?height ?(focusable = false) ?render () =
  Result.bind (Renderable.Private.create context ?id ()) (fun renderable ->
      let value =
        {
          renderable;
          children = Layout_children.Private.of_renderable renderable;
          render;
        }
      in
      Renderable.Private.set_behavior renderable
        (Renderable.Private.make_behavior ~render_self:(draw value) ());
      let configure result operation =
        match result with Error _ as error -> error | Ok () -> operation ()
      in
      let result =
        configure (Ok ()) (fun () ->
            match width with None -> Ok () | Some width -> Renderable.set_width renderable width)
      in
      let result =
        configure result (fun () ->
            match height with None -> Ok () | Some height -> Renderable.set_height renderable height)
      in
      let result =
        configure result (fun () ->
            if focusable then Renderable.set_focusable renderable true else Ok ())
      in
      match result with
      | Ok () -> Ok value
      | Error error ->
          Renderable.destroy renderable;
          Error error)

let as_renderable value = value.renderable
let children value = value.children

let set_render value render =
  if Renderable.is_destroyed value.renderable then Error Error.Destroyed
  else begin
    value.render <- render;
    Renderable.request_render value.renderable
  end

let destroy value = Renderable.destroy_recursively value.renderable
