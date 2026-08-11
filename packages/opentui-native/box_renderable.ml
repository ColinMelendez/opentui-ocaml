type border_style = No_border | Single | Double | Rounded | Heavy

type t = {
  node : Layout.Node.t;
  mutable background : Color.t;
  mutable border : border_style;
  mutable border_color : Color.t;
  mutable should_fill : bool;
}

let create ~node ?(background = Color.black) ?(border = No_border)
    ?(border_color = Color.white) ?(should_fill = false) () =
  { node; background; border; border_color; should_fill }

let background box = box.background
let set_background box ~background = box.background <- background
let border box = box.border
let set_border box ~border = box.border <- border
let border_color box = box.border_color
let set_border_color box ~border_color = box.border_color <- border_color
let should_fill box = box.should_fill
let set_should_fill box ~should_fill = box.should_fill <- should_fill

let invalid_coordinate = Error.Native Opentui_raw.Error.Invalid_argument

let coordinate value =
  let max_coordinate = Int32.to_float Int32.max_int in
  match classify_float value with
  | FP_nan | FP_infinite -> Error invalid_coordinate
  | FP_zero | FP_subnormal | FP_normal ->
      if Float.compare value 0.0 < 0
         || Float.compare value max_coordinate > 0
      then Error invalid_coordinate
      else Ok (Int32.of_float value)

let extent value = coordinate value

let border_character style ~left ~top ~right ~bottom =
  match style with
  | No_border -> 0l
  | Single ->
      if top && left then 0x250cl
      else if top && right then 0x2510l
      else if bottom && left then 0x2514l
      else if bottom && right then 0x2518l
      else if top || bottom then 0x2500l
      else if left || right then 0x2502l
      else 0l
  | Double ->
      if top && left then 0x2554l
      else if top && right then 0x2557l
      else if bottom && left then 0x255al
      else if bottom && right then 0x255dl
      else if top || bottom then 0x2550l
      else if left || right then 0x2551l
      else 0l
  | Rounded ->
      if top && left then 0x256dl
      else if top && right then 0x256el
      else if bottom && left then 0x2570l
      else if bottom && right then 0x256fl
      else if top || bottom then 0x2500l
      else if left || right then 0x2502l
      else 0l
  | Heavy ->
      if top && left then 0x250fl
      else if top && right then 0x2513l
      else if bottom && left then 0x2517l
      else if bottom && right then 0x251bl
      else if top || bottom then 0x2501l
      else if left || right then 0x2503l
      else 0l

let draw box frame ~offset_x ~offset_y =
  match Layout.Node.layout box.node with
  | Error error -> Error error
  | Ok layout ->
      (match
         coordinate (layout.Layout.left +. offset_x),
         coordinate (layout.Layout.top +. offset_y),
         extent layout.Layout.width,
         extent layout.Layout.height
       with
      | Error error, _, _, _
      | _, Error error, _, _
      | _, _, Error error, _
      | _, _, _, Error error -> Error error
      | Ok x, Ok y, Ok width, Ok height ->
          let width = Int32.to_int width in
          let height = Int32.to_int height in
          if Int.compare width 0 <= 0 || Int.compare height 0 <= 0 then Ok ()
          else
            let no_border =
              match box.border with No_border -> true | Single | Double | Rounded | Heavy -> false
            in
            if no_border && not box.should_fill then Ok ()
            else
              let result = ref (Ok ()) in
              let failed = ref false in
              let right_x = Int32.add x (Int32.of_int (width - 1)) in
              let bottom_y = Int32.add y (Int32.of_int (height - 1)) in
              let attempt_set_cell column row cell_x cell_y =
                let is_left = Int.equal column 0 in
                let is_right = Int.equal column (width - 1) in
                let is_top = Int.equal row 0 in
                let is_bottom = Int.equal row (height - 1) in
                let border_character =
                  border_character box.border ~left:is_left ~top:is_top
                    ~right:is_right ~bottom:is_bottom
                in
                let draws_border =
                  not (Int.equal (Int32.compare border_character 0l) 0)
                in
                if draws_border || box.should_fill then
                  let character =
                    if draws_border then border_character else 0x20l
                  in
                  (match
                     Renderer.Frame.set_cell frame ~x:cell_x ~y:cell_y
                       ~character ~foreground:box.border_color
                       ~background:box.background ~attributes:0l
                   with
                  | Ok () -> ()
                  | Error error ->
                      result := Error error;
                      failed := true)
              in
              let draw_full_row row cell_y =
                let column = ref 0 in
                let cell_x = ref x in
                while !column < width && not !failed do
                  attempt_set_cell !column row !cell_x cell_y;
                  cell_x := Int32.add !cell_x 1l;
                  column := !column + 1
                done
              in
              let draw_side_cells row cell_y =
                attempt_set_cell 0 row x cell_y;
                if width > 1 && not !failed then
                  attempt_set_cell (width - 1) row right_x cell_y
              in
              if box.should_fill then begin
                let row = ref 0 in
                let cell_y = ref y in
                while !row < height && not !failed do
                  draw_full_row !row !cell_y;
                  cell_y := Int32.add !cell_y 1l;
                  row := !row + 1
                done
              end else begin
                draw_full_row 0 y;
                if height > 1 && not !failed then begin
                  let row = ref 1 in
                  let cell_y = ref (Int32.add y 1l) in
                  while !row < height - 1 && not !failed do
                    draw_side_cells !row !cell_y;
                    cell_y := Int32.add !cell_y 1l;
                    row := !row + 1
                  done;
                  if not !failed then draw_full_row (height - 1) bottom_y
                end
              end;
              !result)
