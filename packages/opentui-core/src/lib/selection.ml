type point = { x : float; y : float }
type bounds = { x : float; y : float; width : float; height : float }

type selectable = { id : int; x : float; y : float; destroyed : bool; text : string }

type t = {
  mutable anchor : point;
  mutable focus : point;
  mutable selected_renderables : selectable list;
  mutable touched_renderables : selectable list;
  mutable active : bool;
  mutable dragging : bool;
  mutable start : bool;
}

let create ~anchor:anchor_point ~focus =
  {
    anchor = anchor_point;
    focus;
    selected_renderables = [];
    touched_renderables = [];
    active = true;
    dragging = true;
    start = false;
  }

let anchor selection =
  selection.anchor

let focus selection = selection.focus
let set_focus selection point = selection.focus <- point
let is_start selection = selection.start
let set_is_start selection value = selection.start <- value
let is_active selection = selection.active
let set_active selection value = selection.active <- value
let is_dragging selection = selection.dragging
let set_dragging selection value = selection.dragging <- value
let bounds selection =
  let anchor = anchor selection in
  let minimum_x = min anchor.x selection.focus.x in
  let maximum_x = max anchor.x selection.focus.x in
  let minimum_y = min anchor.y selection.focus.y in
  let maximum_y = max anchor.y selection.focus.y in
  {
    x = minimum_x;
    y = minimum_y;
    width = maximum_x -. minimum_x +. 1.0;
    height = maximum_y -. minimum_y +. 1.0;
  }

let selected_renderables selection = selection.selected_renderables
let touched_renderables selection = selection.touched_renderables
let update_selected_renderables selection values = selection.selected_renderables <- values
let update_touched_renderables selection values = selection.touched_renderables <- values

let selected_text selection =
  let sorted =
    List.sort
      (fun left right ->
        let y_order = Float.compare left.y right.y in
        if not (Int.equal y_order 0) then y_order
        else Float.compare left.x right.x)
      (List.filter (fun renderable -> not renderable.destroyed) selection.selected_renderables)
  in
  let lines = Hashtbl.create 8 in
  List.iter
    (fun renderable ->
      let text = renderable.text in
      if String.length text > 0 then
        let pieces = String.split_on_char '\n' text in
        List.iteri
          (fun index piece ->
            let line = int_of_float renderable.y + index in
            let current = Option.value (Hashtbl.find_opt lines line) ~default:[] in
            Hashtbl.replace lines line
              ((int_of_float renderable.x, piece) :: current))
          pieces)
    sorted;
  let line_numbers = Hashtbl.to_seq_keys lines |> List.of_seq |> List.sort Int.compare in
  String.concat "\n"
    (List.map
       (fun line ->
         let pieces =
           List.sort
             (fun (left, _) (right, _) -> Int.compare left right)
             (Hashtbl.find lines line)
         in
         String.concat "" (List.map snd pieces))
       line_numbers)

type local_bounds = {
  anchor_x : float;
  anchor_y : float;
  focus_x : float;
  focus_y : float;
  is_active : bool;
}

let convert_global_to_local selection ~local_x ~local_y =
  match selection with
  | None -> None
  | Some selection when not selection.active -> None
  | Some selection ->
      let anchor = anchor selection in
      Some
        {
          anchor_x = anchor.x -. local_x;
          anchor_y = anchor.y -. local_y;
          focus_x = selection.focus.x -. local_x;
          focus_y = selection.focus.y -. local_y;
          is_active = true;
        }
