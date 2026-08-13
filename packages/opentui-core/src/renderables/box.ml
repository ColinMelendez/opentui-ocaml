type border_sides = {
  left : bool;
  top : bool;
  right : bool;
  bottom : bool;
}

type t = {
  renderable : Renderable.t;
  children : Layout_children.t;
  mutable border : border_sides;
}

let no_border = { left = false; top = false; right = false; bottom = false }
let all_borders = { left = true; top = true; right = true; bottom = true }

let create context ?id () =
  match Renderable.Private.create context ?id () with
  | Error error -> Error error
  | Ok renderable ->
      let box =
        {
          renderable;
          children = Layout_children.Private.of_renderable renderable;
          border = no_border;
        }
      in
      let behavior =
        Renderable.Private.make_behavior
          ~render_self:(fun _ _ _ ->
            let border = box.border in
            if border.left || border.top || border.right || border.bottom then
              Error Error.Unsupported
            else Ok ())
          ()
      in
      Renderable.Private.set_behavior renderable behavior;
      Ok box

let as_renderable box = box.renderable
let children box = box.children
let border box = box.border

let set_border_side renderable edge enabled =
  Renderable.set_border renderable ~edge
    ~value:(Some (if enabled then 1.0 else 0.0))

let set_border box value =
  let renderable = box.renderable in
  let previous = box.border in
  let rollback () =
    ignore (set_border_side renderable Yoga.Left previous.left);
    ignore (set_border_side renderable Yoga.Top previous.top);
    ignore (set_border_side renderable Yoga.Right previous.right);
    ignore (set_border_side renderable Yoga.Bottom previous.bottom)
  in
  match set_border_side renderable Yoga.Left value.left with
  | Error error -> Error error
  | Ok () ->
      (match set_border_side renderable Yoga.Top value.top with
      | Error error ->
          rollback ();
          Error error
      | Ok () ->
          (match set_border_side renderable Yoga.Right value.right with
          | Error error ->
              rollback ();
              Error error
          | Ok () ->
              (match set_border_side renderable Yoga.Bottom value.bottom with
              | Error error ->
                  rollback ();
                  Error error
              | Ok () ->
                  box.border <- value;
                  Ok ())))

let set_gap box ~gutter value =
  Renderable.set_gap box.renderable ~gutter value

let width box = Renderable.width box.renderable
let height box = Renderable.height box.renderable
let set_width box value = Renderable.set_width box.renderable value
let set_height box value = Renderable.set_height box.renderable value

let visible box = Renderable.visible box.renderable
let set_visible box value = Renderable.set_visible box.renderable value
let opacity box = Renderable.opacity box.renderable
let set_opacity box value = Renderable.set_opacity box.renderable value
let z_index box = Renderable.z_index box.renderable
let set_z_index box value = Renderable.set_z_index box.renderable value

let focusable box = Renderable.focusable box.renderable
let set_focusable box value = Renderable.set_focusable box.renderable value
let focus box = Renderable.focus box.renderable
let blur box = Renderable.blur box.renderable
let destroy box = Renderable.destroy box.renderable
let destroy_recursively box = Renderable.destroy_recursively box.renderable
