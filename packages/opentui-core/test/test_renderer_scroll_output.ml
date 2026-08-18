open Windtrap

module Core = Opentui_core
module Renderer = Core.Renderer
module Renderable = Core.Renderable

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Core.Error.message error)

let attach renderer renderable =
  ignore
    (expect_ok
       (Core.Layout_children.add (Renderer.children renderer) renderable))

let frame_bytes chunks = String.concat "" (List.map Bytes.to_string chunks)

let count_substring value substring =
  let value_length = String.length value in
  let substring_length = String.length substring in
  if substring_length = 0 then 0
  else
    let count = ref 0 in
    let index = ref 0 in
    while !index <= value_length - substring_length do
      if String.equal
           (String.sub value !index substring_length)
           substring
      then begin
        incr count;
        index := !index + substring_length
      end else incr index
    done;
    !count

let frame_at frames index =
  match List.nth_opt !frames index with
  | Some frame -> frame
  | None -> fail "renderer did not deliver the expected number of frames"

type screen = {
  width : int;
  height : int;
  cells : char array array;
}

let make_screen ~width ~height =
  { width; height; cells = Array.make_matrix height width ' ' }

let parse_cursor_position params =
  match String.split_on_char ';' params with
  | [ row; column ] ->
      (match int_of_string_opt row, int_of_string_opt column with
       | Some row, Some column when row > 0 && column > 0 ->
           Some (column - 1, row - 1)
       | Some _, Some _ | None, None | None, Some _ | Some _, None -> None)
  | _ -> None

let apply_frame screen frame =
  let x = ref 0 in
  let y = ref 0 in
  let index = ref 0 in
  let length = String.length frame in
  let write character =
    if
      !x >= 0 && !x < screen.width
      && !y >= 0 && !y < screen.height
      && Char.code character >= Char.code ' '
      && Char.code character <= Char.code '~'
    then screen.cells.(!y).(!x) <- character;
    incr x
  in
  while !index < length do
    match frame.[!index] with
    | '\027' when !index + 1 < length && Char.equal frame.[!index + 1] '[' ->
        let cursor = ref (!index + 2) in
        while
          !cursor < length
          && not
               (Char.code frame.[!cursor] >= Char.code '@'
               && Char.code frame.[!cursor] <= Char.code '~')
        do
          incr cursor
        done;
        if !cursor < length then begin
          let final = frame.[!cursor] in
          if Char.equal final 'H' then begin
            let params = String.sub frame (!index + 2) (!cursor - !index - 2) in
            (match parse_cursor_position params with
             | Some (new_x, new_y) ->
                 x := new_x;
                 y := new_y
             | None -> ())
          end;
          index := !cursor + 1
        end else index := length
    | '\027' -> index := min length (!index + 2)
    | '\n' ->
        incr y;
        x := 0;
        incr index
    | '\r' ->
        x := 0;
        incr index
    | character ->
        write character;
        incr index
  done

let first_column screen =
  Array.init screen.height (fun row -> screen.cells.(row).(0))

let assert_char_array expected actual =
  equal int (Array.length expected) (Array.length actual);
  Array.iteri (fun index character -> equal char character actual.(index)) expected

let snapshot_first_column renderer =
  let buffer = expect_ok (Renderer.current_buffer renderer) in
  let snapshot = expect_ok (Core.Buffer.cell_snapshot buffer) in
  let characters, _, _, _ = snapshot.cells in
  let width = Int32.to_int snapshot.width in
  Array.init (Int32.to_int snapshot.height) (fun row ->
      Char.chr (Int32.to_int characters.(row * width)))

let make_row context ~character () =
  let renderable = expect_ok (Renderable.Private.create context ()) in
  let render_self renderable buffer _delta_time =
    let x = int_of_float (Float.floor (Renderable.screen_x renderable)) in
    let y = int_of_float (Float.floor (Renderable.screen_y renderable)) in
    if x < 0 || y < 0 || x >= 10 || y >= 3 then Ok ()
    else
      Core.Buffer.set_cell buffer ~x:(Int32.of_int x) ~y:(Int32.of_int y)
        ~character:(Int32.of_int character) ~foreground:Core.Color.white
        ~background:Core.Color.black ~attributes:0l
  in
  let behavior = Renderable.Private.make_behavior ~render_self () in
  Renderable.Private.set_behavior renderable behavior;
  ignore (expect_ok (Renderable.set_width renderable (Core.Yoga.Point 8.0)));
  ignore (expect_ok (Renderable.set_height renderable (Core.Yoga.Point 1.0)));
  renderable

let () =
  run "opentui-core-renderer-scroll-output"
    [
      test "translated ScrollBox frames are atomic and replay to the committed grid"
        (fun () ->
          let frames = ref [] in
          let sink =
            Renderer.Output.sink ~write_frame:(fun chunks ->
                frames := !frames @ [ List.map Bytes.copy chunks ];
                Ok ())
          in
          let renderer =
            expect_ok
              (Renderer.create ~output:(Renderer.Output.Sink sink)
                 ~remote_mode:Renderer.Output.Remote ~width:10l ~height:3l ())
          in
          let box =
            expect_ok
              (Core.Renderables.Scroll_box.create (Renderer.context renderer)
                 ~scroll_y:true ~viewport_culling:false
                 ~width:(Core.Yoga.Point 10.0) ~height:(Core.Yoga.Point 3.0) ())
          in
          let vertical = Core.Renderables.Scroll_box.vertical_scrollbar box in
          ignore (expect_ok (Core.Renderables.Scroll_bar.set_visible vertical false));
          let context = Renderer.context renderer in
          let rows =
            [
              make_row context ~character:(Char.code 'A') ();
              make_row context ~character:(Char.code 'B') ();
              make_row context ~character:(Char.code 'C') ();
              make_row context ~character:(Char.code 'D') ();
            ]
          in
          List.iter
            (fun renderable ->
              ignore (expect_ok (Core.Renderables.Scroll_box.add box renderable)))
            rows;
          attach renderer (Core.Renderables.Scroll_box.as_renderable box);
          for _ = 1 to 3 do
            ignore (expect_ok (Renderer.render renderer ~force:true))
          done;
          frames := [];
          ignore (expect_ok (Renderer.render renderer ~force:true));
          equal int 1 (List.length !frames);
          assert_char_array [| 'A'; 'B'; 'C' |] (snapshot_first_column renderer);
          ignore (expect_ok (Core.Renderables.Scroll_box.set_scroll_top box 1.0));
          equal (float 0.0001) 1.0 (Core.Renderables.Scroll_box.scroll_top box);
          ignore (expect_ok (Renderer.render renderer ~force:false));
          equal int 2 (List.length !frames);
          assert_char_array [| 'B'; 'C'; 'D' |] (snapshot_first_column renderer);

          let first = frame_bytes (frame_at frames 0) in
          let second = frame_bytes (frame_at frames 1) in
          List.iter
            (fun frame ->
              equal int 1 (count_substring frame "\027[?2026h");
              equal int 1 (count_substring frame "\027[?2026l"))
            [ first; second ];

          let replayed = make_screen ~width:10 ~height:3 in
          apply_frame replayed first;
          assert_char_array [| 'A'; 'B'; 'C' |] (first_column replayed);
          apply_frame replayed second;
          assert_char_array [| 'B'; 'C'; 'D' |] (first_column replayed);
          Renderer.destroy renderer)
    ; test "nested ScrollBox keeps its scrollbar at the trailing edge"
        (fun () ->
          let renderer =
            expect_ok
              (Renderer.create ~output:Renderer.Output.Memory ~width:80l
                 ~height:24l ())
          in
          let parent =
            expect_ok
              (Core.Renderables.Box.create (Renderer.context renderer) ())
          in
          attach renderer (Core.Renderables.Box.as_renderable parent);
          let title =
            expect_ok
              (Core.Renderables.Box.create (Renderer.context renderer)
                 ~border:Core.Renderables.Box.all_borders ())
          in
          ignore
            (expect_ok
               (Renderable.set_height
                  (Core.Renderables.Box.as_renderable title)
                  (Core.Yoga.Point 3.0)));
          ignore
            (expect_ok
               (Core.Layout_children.add
                  (Core.Renderables.Box.children parent)
                  (Core.Renderables.Box.as_renderable title)));
          let box =
            expect_ok
              (Core.Renderables.Scroll_box.create (Renderer.context renderer)
                 ~scroll_y:true ())
          in
          ignore
            (expect_ok
               (Renderable.set_height
                  (Core.Renderables.Scroll_box.as_renderable box)
                  (Core.Yoga.Percent 100.0)));
          ignore
            (expect_ok
               (Core.Layout_children.add
                  (Core.Renderables.Box.children parent)
                  (Core.Renderables.Scroll_box.as_renderable box)));
          let markdown_content =
            String.concat "\n"
              (List.init 31 (fun index -> Printf.sprintf "row %02d" index))
          in
          let markdown =
            expect_ok
              (Core.Renderables.Markdown.create (Renderer.context renderer)
                 ~content:markdown_content ())
          in
          let status =
            expect_ok
              (Core.Renderables.Text.create (Renderer.context renderer)
                 ~content:(Core.Lib.Styled_text.of_string "status") ())
          in
          ignore
            (expect_ok
               (Core.Layout_children.add
                  (Core.Renderables.Box.children parent)
                  (Core.Renderables.Text.as_renderable status)));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          ignore
            (expect_ok
               (Core.Renderables.Scroll_box.add box
                  (Core.Renderables.Markdown.as_renderable markdown)));
          for _ = 1 to 4 do
            ignore (expect_ok (Renderer.render renderer ~force:true))
          done;
          let bar = Core.Renderables.Scroll_box.vertical_scrollbar box in
          let bar_node = Core.Renderables.Scroll_bar.as_renderable bar in
          let slider_node =
            Core.Renderables.Slider.as_renderable
              (Core.Renderables.Scroll_bar.slider bar)
          in
          let bar_x =
            int_of_float
              (Float.floor
                 (Renderable.screen_x bar_node +. Renderable.width bar_node -. 1.0))
          in
          if bar_x < 70 then
            fail
              (Printf.sprintf
                 "scrollbar is not docked: parent=(%f,%f,%f,%f) box=(%f,%f,%f,%f) viewport=(%f,%f,%f,%f) bar=(%f,%f,%f,%f)"
                 (Renderable.screen_x (Core.Renderables.Box.as_renderable parent))
                 (Renderable.screen_y (Core.Renderables.Box.as_renderable parent))
                 (Renderable.width (Core.Renderables.Box.as_renderable parent))
                 (Renderable.height (Core.Renderables.Box.as_renderable parent))
                 (Renderable.screen_x (Core.Renderables.Scroll_box.as_renderable box))
                 (Renderable.screen_y (Core.Renderables.Scroll_box.as_renderable box))
                 (Renderable.width (Core.Renderables.Scroll_box.as_renderable box))
                 (Renderable.height (Core.Renderables.Scroll_box.as_renderable box))
                 (Renderable.screen_x (Core.Renderables.Scroll_box.viewport box))
                 (Renderable.screen_y (Core.Renderables.Scroll_box.viewport box))
                 (Renderable.width (Core.Renderables.Scroll_box.viewport box))
                 (Renderable.height (Core.Renderables.Scroll_box.viewport box))
                 (Renderable.screen_x bar_node) (Renderable.screen_y bar_node)
                 (Renderable.width bar_node) (Renderable.height bar_node));
          equal bool true
            (match expect_ok (Renderer.hit_test renderer ~x:bar_x ~y:4) with
             | Some target -> target == slider_node
             | None -> false);
          Core.Renderables.Markdown.destroy markdown;
          Renderer.destroy renderer)
    ]
