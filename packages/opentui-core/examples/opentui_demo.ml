(* Port of vendor/opentui/packages/examples/src/opentui-demo.ts.

   A tabbed showcase of the OCaml OpenTUI renderables: styled text and color
   gradients, box and border styles (including partial and custom borders),
   box titles, animated elements, and interactive border toggling. *)

module O = Opentui_core
module S = O.Lib.Styled_text
module Box = O.Renderables.Box
module Text = O.Renderables.Text
module Tab_controller = Opentui_examples_lib.Tab_controller
module Util = Opentui_examples_lib.Util

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> invalid_arg (O.Error.message error)

let expect_unit result =
  match result with
  | Ok () -> ()
  | Error error -> invalid_arg (O.Error.message error)

let position_absolute renderable ~left ~top ~z_index =
  ignore (expect_ok (O.Renderable.set_position_type renderable O.Yoga.Position_absolute));
  ignore (expect_ok (O.Renderable.set_position renderable ~edge:O.Yoga.Left (O.Yoga.Point left)));
  ignore (expect_ok (O.Renderable.set_position renderable ~edge:O.Yoga.Top (O.Yoga.Point top)));
  ignore (expect_ok (O.Renderable.set_z_index renderable z_index))

let add_styled_text context group ~id ~content ~left ~top ~fg ~attributes ~z_index () =
  let text =
    expect_ok
      (Text.create context ~id ~content:(S.create [ S.chunk ~fg ~attributes content ]) ())
  in
  position_absolute (Text.as_renderable text) ~left ~top ~z_index;
  ignore (expect_ok (O.Layout_children.add (Box.children group) (Text.as_renderable text)));
  text

let add_box context group ~id ~left ~top ~width ~height ~background_color ?border_style
    ?border ?border_color ?title ?title_alignment ?custom_border_chars ~z_index () : Box.t =
  let box =
    expect_ok
      (Box.create context ~id ~background_color ?border_style ?border ?border_color
         ?title ?title_alignment ?custom_border_chars ())
  in
  position_absolute (Box.as_renderable box) ~left ~top ~z_index;
  ignore (expect_ok (O.Renderable.set_width (Box.as_renderable box) (O.Yoga.Point width)));
  ignore (expect_ok (O.Renderable.set_height (Box.as_renderable box) (O.Yoga.Point height)));
  ignore (expect_ok (O.Layout_children.add (Box.children group) (Box.as_renderable box)));
  box

let border_of_sides ~top ~right ~bottom ~left =
  let sides =
    List.filter_map
      (fun (side, enabled) -> if enabled then Some side else None)
      [ O.Lib.Border.Top, top; O.Lib.Border.Right, right; O.Lib.Border.Bottom, bottom;
        O.Lib.Border.Left, left ]
  in
  O.Lib.Border.Sides sides

let set_text_content text content =
  ignore (expect_ok (Text.set_content text (S.of_string content)))

let set_box_border box border = ignore (expect_ok (Box.set_border box border))
let set_box_background box color = ignore (expect_ok (Box.set_background_color box color))

let block_char = "\226\150\136"

(* ------------------------------------------------------------------ *)
(* Tab: Text & Attributes                                             *)
(* ------------------------------------------------------------------ *)

let text_attributes_tab renderer context =
  let wheel_pixels : (string, Text.t) Hashtbl.t = Hashtbl.create 64 in
  let wheel_center_x = 70 in
  let wheel_center_y = 15 in
  let wheel_radius = 7 in
  let wheel_center_x_f = float_of_int wheel_center_x in
  let wheel_center_y_f = float_of_int wheel_center_y in
  {
    Tab_controller.title = "Text & Attributes";
    init =
      (fun ~group ->
        let yellow = Util.color_of_hex "#FFFF00" in
        let white = O.Color.white in
        let grey = Util.color_of_hex "#CCCCCC" in
        let add_line ~id ~content ~left ~top ~fg ~attributes =
          ignore
            (add_styled_text context group ~id ~content ~left ~top ~fg ~attributes
               ~z_index:10 ())
        in
        ignore
          (add_line ~id:"text-title" ~content:"Text Styling & Color Gradients" ~left:10.
             ~top:5. ~fg:yellow
             ~attributes:(O.Lib.Text_attributes.of_flags ~bold:true ~underline:true ()));
        List.iteri
          (fun index (id, content, attributes) ->
            ignore
              (add_line ~id ~content ~left:10. ~top:(8. +. float_of_int index) ~fg:white
                 ~attributes))
          [ "attr-bold", "Bold Text", O.Lib.Text_attributes.of_flags ~bold:true ()
          ; "attr-italic", "Italic Text", O.Lib.Text_attributes.of_flags ~italic:true ()
          ; "attr-underline", "Underlined Text", O.Lib.Text_attributes.of_flags ~underline:true ()
          ; "attr-dim", "Dim Text", O.Lib.Text_attributes.of_flags ~dim:true ()
          ; "attr-combined", "Bold + Italic + Underline",
            O.Lib.Text_attributes.of_flags ~bold:true ~italic:true ~underline:true () ];
        ignore
          (add_line ~id:"gradient-title" ~content:"Rainbow Gradient:" ~left:10. ~top:15.
             ~fg:grey
             ~attributes:(O.Lib.Text_attributes.of_flags ~underline:true ()));
        for i = 0 to 39 do
          let hue = (float_of_int i /. 40.0) *. 360.0 in
          let color = Util.color_of_hsv hue 1.0 1.0 in
          ignore
            (add_line ~id:(Printf.sprintf "gradient-%d" i) ~content:block_char
               ~left:(10. +. float_of_int i) ~top:17. ~fg:color
               ~attributes:O.Lib.Text_attributes.none)
        done;
        Ok ());
    update =
      (fun ~delta_ms ~group ->
        ignore delta_ms;
        let time = Unix.gettimeofday () in
        let rotation_radians = mod_float (time *. 45.0) 360.0 *. Float.pi /. 180.0 in
        let new_pixels = Hashtbl.create 64 in
        for y = wheel_center_y - wheel_radius to wheel_center_y + wheel_radius do
          for x = wheel_center_x - (wheel_radius * 2) to wheel_center_x + (wheel_radius * 2) do
            let dx = (float_of_int x -. wheel_center_x_f) /. 2.0 in
            let dy = float_of_int y -. wheel_center_y_f in
            let distance = sqrt (dx *. dx +. dy *. dy) in
            if distance <= float_of_int wheel_radius then begin
              let angle = atan2 dy dx in
              let rotated_angle = angle +. rotation_radians in
              let hue = mod_float ((rotated_angle /. Float.pi) *. 180.0 +. 180.0) 360. in
              let saturation = distance /. float_of_int wheel_radius in
              let color = Util.color_of_hsv hue saturation 1.0 in
              let key = Printf.sprintf "wheel-%d-%d" x y in
              Hashtbl.replace new_pixels key ();
              match Hashtbl.find_opt wheel_pixels key with
              | Some existing ->
                  ignore
                    (expect_ok
                       (O.Renderable.set_position (Text.as_renderable existing)
                          ~edge:O.Yoga.Left (O.Yoga.Point (float_of_int x))));
                  ignore
                    (expect_ok
                       (O.Renderable.set_position (Text.as_renderable existing)
                          ~edge:O.Yoga.Top (O.Yoga.Point (float_of_int y))));
                  ignore
                    (expect_ok
                       (Text.set_content existing
                          (S.create [ S.chunk ~fg:color block_char ])))
              | None ->
                  let pixel =
                    add_styled_text context group ~id:key ~content:block_char
                      ~left:(float_of_int x) ~top:(float_of_int y) ~fg:color
                      ~attributes:O.Lib.Text_attributes.none ~z_index:10 ()
                  in
                  Hashtbl.replace wheel_pixels key pixel
            end
          done
        done;
        Hashtbl.iter
          (fun key pixel ->
            if not (Hashtbl.mem new_pixels key) then begin
              ignore
                (expect_ok
                   (O.Layout_children.remove (Box.children group)
                      (Text.as_renderable pixel)));
              (* The pixel rotated out of the wheel: free its retained
                 renderable and native text-buffer handle instead of leaking
                 a native slot every frame. *)
              Text.destroy pixel
            end)
          wheel_pixels;
        let stale = Hashtbl.fold (fun key _ acc -> if Hashtbl.mem new_pixels key then acc else key :: acc) wheel_pixels [] in
        List.iter (fun key -> Hashtbl.remove wheel_pixels key) stale;
        Ok ());
    show = (fun ~group -> ignore group; Hashtbl.clear wheel_pixels);
    hide =
      (fun ~group ->
        Hashtbl.iter
          (fun _ pixel ->
            ignore
              (expect_ok
                 (O.Layout_children.remove (Box.children group)
                    (Text.as_renderable pixel)));
            Text.destroy pixel)
          wheel_pixels;
        Hashtbl.clear wheel_pixels);
  }

(* ------------------------------------------------------------------ *)
(* Tab: Basics                                                         *)
(* ------------------------------------------------------------------ *)

let basics_tab renderer context =
  let cursor_info : Text.t option ref = ref None in
  {
    Tab_controller.title = "Basics";
    init =
      (fun ~group ->
        let white = O.Color.white in
        let yellow = Util.color_of_hex "#FFFF00" in
        let grey = Util.color_of_hex "#CCCCCC" in
        ignore
          (add_styled_text context group ~id:"opentui-title"
             ~content:"Basic CLI Renderer Demo" ~left:10. ~top:5. ~fg:yellow
             ~attributes:(O.Lib.Text_attributes.of_flags ~bold:true ~underline:true ())
             ~z_index:10 ());
        ignore
          (add_box context group ~id:"box1" ~left:10. ~top:8. ~width:20. ~height:8.
             ~background_color:(Util.color_of_hex "#333366")
             ~border_style:O.Lib.Border.Single ~border:O.Lib.Border.All_borders
             ~border_color:white ~z_index:0 ());
        ignore
          (add_styled_text context group ~id:"box1-title" ~content:"Simple Box"
             ~left:12. ~top:10. ~fg:white
             ~attributes:(O.Lib.Text_attributes.of_flags ~bold:true ()) ~z_index:10 ());
        ignore
          (add_box context group ~id:"box2" ~left:35. ~top:10. ~width:25. ~height:6.
             ~background_color:(Util.color_of_hex "#663333")
             ~border_style:O.Lib.Border.Double ~border:O.Lib.Border.All_borders
             ~border_color:yellow ~z_index:1 ());
        ignore
          (add_styled_text context group ~id:"box2-title" ~content:"Double Border Box"
             ~left:37. ~top:12. ~fg:white
             ~attributes:(O.Lib.Text_attributes.of_flags ~bold:true ()) ~z_index:10 ());
        ignore
          (add_styled_text context group ~id:"description"
             ~content:"This tab demonstrates basic box and text rendering with different border styles."
             ~left:10. ~top:18. ~fg:grey ~attributes:0 ~z_index:10 ());
        cursor_info :=
          Some
            (add_styled_text context group ~id:"cursor-info"
               ~content:"Cursor: (0,0) - Style: block" ~left:10. ~top:20. ~fg:white
               ~attributes:(O.Lib.Text_attributes.of_flags ~bold:true ()) ~z_index:10 ());
        Ok ());
    update =
      (fun ~delta_ms ~group ->
        ignore delta_ms;
        ignore group;
        let time = Unix.gettimeofday () in
        let cursor_x = 15 + int_of_float (3. *. cos time) in
        let cursor_y = 13 + int_of_float (2. *. sin time) in
        let style_index = int_of_float (floor (time /. 2.0)) mod 6 in
        let style, blinking =
          match style_index with
          | 0 -> O.Renderer.Block, false
          | 1 -> O.Renderer.Block, true
          | 2 -> O.Renderer.Line, false
          | 3 -> O.Renderer.Line, true
          | 4 -> O.Renderer.Underline, false
          | _ -> O.Renderer.Underline, true
        in
        ignore
          (expect_ok
             (O.Renderer.set_cursor_position renderer ~x:(Int32.of_int cursor_x)
                ~y:(Int32.of_int cursor_y) ()));
        ignore
          (expect_ok
             (O.Renderer.set_cursor_style renderer
                { style = Some style; blinking = Some blinking; color = None; cursor = None }));
        (match !cursor_info with
         | Some text ->
             let style_name =
               match style with
               | Block -> "block"
               | Line -> "line"
               | Underline -> "underline"
               | Default -> "default"
             in
              set_text_content text
                (Printf.sprintf "Cursor: (%d,%d) - Style: %s%s" cursor_x cursor_y style_name
                   (if blinking then " (blinking)" else ""))
          | None -> ());
         Ok ());
    show = (fun ~group ->
        ignore group;
        (* The cursor animation is this tab's content; park the cursor at its
           starting spot and make it visible when the tab is shown. *)
        ignore
          (expect_ok
             (O.Renderer.set_cursor_position renderer ~x:15l ~y:13l ~visible:true ())));
    hide = (fun ~group ->
        ignore group;
        ignore
          (expect_ok
             (O.Renderer.set_cursor_position renderer ~x:1l ~y:1l ~visible:false ())));
  }

(* ------------------------------------------------------------------ *)
(* Tab: Borders                                                        *)
(* ------------------------------------------------------------------ *)

let borders_tab renderer context =
  let partial_border_phase = ref 0 in
  let partial_animated : Box.t option ref = ref None in
  let partial_phase_text : Text.t option ref = ref None in
  let ascii_codepoints = Array.make 11 (Int32.of_int (Char.code '+')) in
  let block_codepoints = Array.make 11 (Int32.of_int 0x2588) in
  let star_codepoints = Array.make 11 (Int32.of_int (Char.code '*')) in
  {
    Tab_controller.title = "Borders";
    init =
      (fun ~group ->
        let white = O.Color.white in
        let yellow = Util.color_of_hex "#FFFF00" in
        let grey = Util.color_of_hex "#CCCCCC" in
        ignore
          (add_styled_text context group ~id:"border-title"
             ~content:"Border Styles & Partial Borders" ~left:10. ~top:5. ~fg:yellow
             ~attributes:(O.Lib.Text_attributes.of_flags ~bold:true ~underline:true ())
             ~z_index:10 ());
        ignore
          (add_box context group ~id:"single-box" ~left:10. ~top:8. ~width:15. ~height:5.
             ~background_color:(Util.color_of_hex "#222244")
             ~border_style:O.Lib.Border.Single ~border:O.Lib.Border.All_borders
             ~border_color:white ~z_index:0 ());
        ignore
          (add_styled_text context group ~id:"single-label" ~content:"Single"
             ~left:12. ~top:10. ~fg:white
             ~attributes:(O.Lib.Text_attributes.of_flags ~bold:true ()) ~z_index:10 ());
        ignore
          (add_box context group ~id:"double-box" ~left:30. ~top:8. ~width:15. ~height:5.
             ~background_color:(Util.color_of_hex "#442222")
             ~border_style:O.Lib.Border.Double ~border:O.Lib.Border.All_borders
             ~border_color:white ~z_index:0 ());
        ignore
          (add_styled_text context group ~id:"double-label" ~content:"Double"
             ~left:32. ~top:10. ~fg:white
             ~attributes:(O.Lib.Text_attributes.of_flags ~bold:true ()) ~z_index:10 ());
        ignore
          (add_box context group ~id:"rounded-box" ~left:50. ~top:8. ~width:15. ~height:5.
             ~background_color:(Util.color_of_hex "#224422")
             ~border_style:O.Lib.Border.Rounded ~border:O.Lib.Border.All_borders
             ~border_color:white ~z_index:0 ());
        ignore
          (add_styled_text context group ~id:"rounded-label" ~content:"Rounded"
             ~left:52. ~top:10. ~fg:white
             ~attributes:(O.Lib.Text_attributes.of_flags ~bold:true ()) ~z_index:10 ());
        ignore
          (add_styled_text context group ~id:"partial-title" ~content:"Partial Borders:"
             ~left:10. ~top:15. ~fg:grey
             ~attributes:(O.Lib.Text_attributes.of_flags ~underline:true ()) ~z_index:10 ());
        ignore
          (add_box context group ~id:"partial-left" ~left:10. ~top:17. ~width:12. ~height:4.
             ~background_color:(Util.color_of_hex "#222244")
             ~border_style:O.Lib.Border.Single
             ~border:(O.Lib.Border.Sides [ O.Lib.Border.Left ]) ~border_color:white
             ~z_index:0 ());
        ignore
          (add_styled_text context group ~id:"partial-left-label" ~content:"Left Only"
             ~left:12. ~top:18. ~fg:white ~attributes:0 ~z_index:10 ());
        partial_animated :=
          Some
            (add_box context group ~id:"partial-animated" ~left:30. ~top:17. ~width:20.
               ~height:4. ~background_color:(Util.color_of_hex "#334455")
               ~border_style:O.Lib.Border.Single ~border:O.Lib.Border.All_borders
               ~border_color:white ~z_index:0 ());
        ignore
          (add_styled_text context group ~id:"partial-animated-label"
             ~content:"Animated Borders" ~left:32. ~top:18. ~fg:white ~attributes:0
             ~z_index:10 ());
        partial_phase_text :=
          Some
            (add_styled_text context group ~id:"partial-phase" ~content:"Phase: 1/8"
               ~left:30. ~top:22. ~fg:(Util.color_of_hex "#AAAAAA") ~attributes:0
               ~z_index:10 ());
        ignore
          (add_styled_text context group ~id:"custom-border-title"
             ~content:"Custom Border Characters:" ~left:10. ~top:25. ~fg:grey
             ~attributes:(O.Lib.Text_attributes.of_flags ~underline:true ()) ~z_index:10 ());
        let ascii = expect_ok (O.Lib.Border.of_codepoints ascii_codepoints) in
        let block = expect_ok (O.Lib.Border.of_codepoints block_codepoints) in
        let stars = expect_ok (O.Lib.Border.of_codepoints star_codepoints) in
        ignore
          (add_box context group ~id:"ascii-box" ~left:10. ~top:27. ~width:15. ~height:5.
             ~background_color:(Util.color_of_hex "#222244")
             ~border_style:O.Lib.Border.Single ~border:O.Lib.Border.All_borders
             ~border_color:white ~custom_border_chars:ascii ~z_index:0 ());
        ignore
          (add_styled_text context group ~id:"ascii-label" ~content:"ASCII Border"
             ~left:12. ~top:29. ~fg:white
             ~attributes:(O.Lib.Text_attributes.of_flags ~bold:true ()) ~z_index:10 ());
        ignore
          (add_box context group ~id:"block-box" ~left:30. ~top:27. ~width:15. ~height:5.
             ~background_color:(Util.color_of_hex "#442222")
             ~border_style:O.Lib.Border.Single ~border:O.Lib.Border.All_borders
             ~border_color:white ~custom_border_chars:block ~z_index:0 ());
        ignore
          (add_styled_text context group ~id:"block-label" ~content:"Block Border"
             ~left:32. ~top:29. ~fg:white
             ~attributes:(O.Lib.Text_attributes.of_flags ~bold:true ()) ~z_index:10 ());
        ignore
          (add_box context group ~id:"star-box" ~left:50. ~top:27. ~width:15. ~height:5.
             ~background_color:(Util.color_of_hex "#224422")
             ~border_style:O.Lib.Border.Single ~border:O.Lib.Border.All_borders
             ~border_color:white ~custom_border_chars:stars ~z_index:0 ());
        ignore
          (add_styled_text context group ~id:"star-label" ~content:"Star Border"
             ~left:52. ~top:29. ~fg:white
             ~attributes:(O.Lib.Text_attributes.of_flags ~bold:true ()) ~z_index:10 ());
        Ok ());
    update =
      (fun ~delta_ms ~group ->
        ignore delta_ms;
        ignore group;
        let time = Unix.gettimeofday () in
        let phase = int_of_float (Float.rem time 8.0) mod 8 in
        if not (Int.equal phase !partial_border_phase) then begin
          partial_border_phase := phase;
          let top = List.mem phase [ 0; 3; 5; 7 ] in
          let right = List.mem phase [ 1; 3; 6; 7 ] in
          let bottom = List.mem phase [ 2; 3; 5; 7 ] in
          let left = List.mem phase [ 4; 5; 6; 7 ] in
          Option.iter
            (fun box ->
              set_box_border box (border_of_sides ~top ~right ~bottom ~left))
            !partial_animated;
          Option.iter
            (fun text -> set_text_content text (Printf.sprintf "Phase: %d/8" (phase + 1)))
            !partial_phase_text
        end;
        Ok ());
    show = (fun ~group -> ignore group);
    hide = (fun ~group -> ignore group);
  }

(* ------------------------------------------------------------------ *)
(* Tab: Animation                                                      *)
(* ------------------------------------------------------------------ *)

let animation_tab renderer context =
  let anim_position = ref 5.0 in
  let anim_direction = ref 1 in
  let moving_text : Text.t option ref = ref None in
  let animated_box : Box.t option ref = ref None in
  let color_box : Box.t option ref = ref None in
  {
    Tab_controller.title = "Animation";
    init =
      (fun ~group ->
        let yellow = Util.color_of_hex "#FFFF00" in
        let green = Util.color_of_hex "#00FF00" in
        let magenta = Util.color_of_hex "#FF00FF" in
        let white = O.Color.white in
        ignore
          (add_styled_text context group ~id:"anim-title"
             ~content:"Animation Demonstrations" ~left:10. ~top:5. ~fg:yellow
             ~attributes:(O.Lib.Text_attributes.of_flags ~bold:true ~underline:true ())
             ~z_index:10 ());
        moving_text :=
          Some
            (add_styled_text context group ~id:"moving-text" ~content:"Moving Text"
               ~left:!anim_position ~top:8. ~fg:green
               ~attributes:(O.Lib.Text_attributes.of_flags ~bold:true ~underline:true ())
               ~z_index:10 ());
        animated_box :=
          Some
            (add_box context group ~id:"animated-box" ~left:!anim_position ~top:10. ~width:10.
               ~height:3. ~background_color:(Util.color_of_hex "#550055")
               ~border_style:O.Lib.Border.Rounded ~border:O.Lib.Border.All_borders
               ~border_color:magenta ~z_index:0 ());
        color_box :=
          Some
            (add_box context group ~id:"color-box" ~left:50. ~top:12. ~width:18. ~height:5.
               ~background_color:(Util.color_of_hex "#550055")
               ~border_style:O.Lib.Border.Double ~border:O.Lib.Border.All_borders
               ~border_color:white ~z_index:0 ());
        ignore
          (add_styled_text context group ~id:"color-box-title" ~content:"Animated Color"
             ~left:52. ~top:14. ~fg:white
             ~attributes:(O.Lib.Text_attributes.of_flags ~bold:true ()) ~z_index:10 ());
        Ok ());
    update =
      (fun ~delta_ms ~group ->
        ignore group;
        let delta_time = Float.min (delta_ms /. 1000.0) 0.1 in
        anim_position :=
          !anim_position +. (float_of_int !anim_direction *. 15. *. delta_time);
        if !anim_position > 40. then begin
          anim_position := 40.;
          anim_direction := -1
        end
        else if !anim_position < 5. then begin
          anim_position := 5.;
          anim_direction := 1
        end;
        let x = Float.round !anim_position in
        Option.iter
          (fun text ->
            ignore
              (expect_ok
                 (O.Renderable.set_position (Text.as_renderable text)
                    ~edge:O.Yoga.Left (O.Yoga.Point x))))
          !moving_text;
        Option.iter
          (fun box ->
            ignore
              (expect_ok
                 (O.Renderable.set_position (Box.as_renderable box)
                    ~edge:O.Yoga.Left (O.Yoga.Point x))))
          !animated_box;
        Option.iter
          (fun box ->
            let time = Unix.gettimeofday () in
            let hue = mod_float (time *. 30.0) 360. in
            set_box_background box (Util.color_of_hsv hue 1.0 0.7))
          !color_box;
        Ok ());
    show = (fun ~group -> ignore group);
    hide = (fun ~group -> ignore group);
  }

(* ------------------------------------------------------------------ *)
(* Tab: Titles                                                         *)
(* ------------------------------------------------------------------ *)

let titles_tab renderer context =
  {
    Tab_controller.title = "Titles";
    init =
      (fun ~group ->
        let yellow = Util.color_of_hex "#FFFF00" in
        let white = O.Color.white in
        ignore
          (add_styled_text context group ~id:"layout-title" ~content:"Box Titles"
             ~left:10. ~top:5. ~fg:yellow
             ~attributes:(O.Lib.Text_attributes.of_flags ~bold:true ~underline:true ())
             ~z_index:10 ());
        ignore
          (add_box context group ~id:"titled-left" ~left:10. ~top:8. ~width:20. ~height:5.
             ~background_color:(Util.color_of_hex "#222244")
             ~border_style:O.Lib.Border.Single ~border:O.Lib.Border.All_borders
             ~border_color:white ~title:"Left Aligned" ~title_alignment:O.Lib.Border.Left
             ~z_index:0 ());
        ignore
          (add_box context group ~id:"titled-center" ~left:35. ~top:8. ~width:20. ~height:5.
             ~background_color:(Util.color_of_hex "#442222")
             ~border_style:O.Lib.Border.Double ~border:O.Lib.Border.All_borders
             ~border_color:white ~title:"Centered Title" ~title_alignment:O.Lib.Border.Center
             ~z_index:0 ());
        ignore
          (add_box context group ~id:"titled-right" ~left:60. ~top:8. ~width:20. ~height:5.
             ~background_color:(Util.color_of_hex "#224422")
             ~border_style:O.Lib.Border.Rounded ~border:O.Lib.Border.All_borders
             ~border_color:white ~title:"Right Aligned" ~title_alignment:O.Lib.Border.Right
             ~z_index:0 ());
        Ok ());
    update = (fun ~delta_ms ~group -> ignore delta_ms; ignore group; Ok ());
    show = (fun ~group -> ignore group);
    hide = (fun ~group -> ignore group);
  }

(* ------------------------------------------------------------------ *)
(* Tab: Interactive                                                    *)
(* ------------------------------------------------------------------ *)

let interactive_tab renderer context =
  let border_top = ref true in
  let border_right = ref true in
  let border_bottom = ref true in
  let border_left = ref true in
  let interactive_border : Box.t option ref = ref None in
  let border_state : Text.t option ref = ref None in
  let toggle_border raw =
    match raw with
    | Some raw
      when Bytes.equal raw (Bytes.of_string "t") || Bytes.equal raw (Bytes.of_string "T") ->
        border_top := not !border_top
    | Some raw
      when Bytes.equal raw (Bytes.of_string "r") || Bytes.equal raw (Bytes.of_string "R") ->
        border_right := not !border_right
    | Some raw
      when Bytes.equal raw (Bytes.of_string "b") || Bytes.equal raw (Bytes.of_string "B") ->
        border_bottom := not !border_bottom
    | Some raw
      when Bytes.equal raw (Bytes.of_string "l") || Bytes.equal raw (Bytes.of_string "L") ->
        border_left := not !border_left
    | _ -> ()
  in
  {
    Tab_controller.title = "Interactive";
    init =
      (fun ~group ->
        let yellow = Util.color_of_hex "#FFFF00" in
        let white = O.Color.white in
        let light = Util.color_of_hex "#CCCCCC" in
        let dim = Util.color_of_hex "#AAAAAA" in
        ignore
          (add_styled_text context group ~id:"interactive-title"
             ~content:"Interactive Controls" ~left:10. ~top:5. ~fg:yellow
             ~attributes:(O.Lib.Text_attributes.of_flags ~bold:true ~underline:true ())
             ~z_index:10 ());
        interactive_border :=
          Some
            (add_box context group ~id:"interactive-border" ~left:15. ~top:8. ~width:40.
               ~height:8. ~background_color:(Util.color_of_hex "#333344")
               ~border_style:O.Lib.Border.Double ~border:O.Lib.Border.All_borders
               ~border_color:white ~z_index:0 ());
        ignore
          (add_styled_text context group ~id:"interactive-label"
             ~content:"Press keys to toggle borders" ~left:22. ~top:12. ~fg:white
             ~attributes:(O.Lib.Text_attributes.of_flags ~bold:true ()) ~z_index:10 ());
        ignore
          (add_styled_text context group ~id:"interactive-instructions"
             ~content:"Keyboard Controls:" ~left:10. ~top:18. ~fg:white
             ~attributes:(O.Lib.Text_attributes.of_flags ~underline:true ()) ~z_index:10 ());
        List.iteri
          (fun index (id, label) ->
            ignore
              (add_styled_text context group ~id ~content:label ~left:10.
                 ~top:(19. +. float_of_int index) ~fg:light ~attributes:0 ~z_index:10 ()))
          [ "key-t", "T - Toggle top border"; "key-r", "R - Toggle right border";
            "key-b", "B - Toggle bottom border"; "key-l", "L - Toggle left border" ];
        border_state :=
          Some
            (add_styled_text context group ~id:"border-state" ~content:"Active borders: All"
               ~left:10. ~top:24. ~fg:dim ~attributes:0 ~z_index:10 ());
        Ok ());
    update =
      (fun ~delta_ms ~group ->
        ignore delta_ms;
        ignore group;
        Option.iter
          (fun box ->
            set_box_border box
              (border_of_sides ~top:!border_top ~right:!border_right
                 ~bottom:!border_bottom ~left:!border_left))
          !interactive_border;
        let parts =
          List.filter_map
            (fun (enabled, name) -> if enabled then Some name else None)
            [ !border_top, "Top"; !border_right, "Right"; !border_bottom, "Bottom";
              !border_left, "Left" ]
        in
        let description = match parts with [] -> "None" | _ -> String.concat " " parts in
        Option.iter
          (fun text -> set_text_content text ("Active borders: " ^ description))
          !border_state;
        Ok ());
    show = (fun ~group -> ignore group);
    hide = (fun ~group -> ignore group);
  },
  toggle_border

(* ------------------------------------------------------------------ *)
(* Main                                                                *)
(* ------------------------------------------------------------------ *)

let run renderer ~exit =
  (* The reference demo calls [renderer.start()] because its tab showcase
     contains per-frame animations. Own the equivalent live request here so
     the shared harness can remain on-demand for other examples. *)
  let live_lease = expect_ok (O.Renderer.acquire_live_lease renderer) in
  ignore
    (expect_ok
       (O.Renderer.attach_before_destroy renderer (fun () ->
            O.Renderer.release_live_lease live_lease)));
  ignore
    (expect_ok
       (O.Renderer.set_background_color renderer
          ~color:(Util.color_of_hex "#000028")));
  let context = O.Renderer.context renderer in
  let controller =
    Tab_controller.create ~renderer ~id:"main-tab-controller"
      ~text_color:O.Color.white
      ~selected_background_color:(Util.color_of_hex "#333333")
      ~selected_text_color:(Util.color_of_hex "#FFFF00")
      ~selected_description_color:O.Color.white ()
  in
  ignore
    (expect_ok
       (O.Layout_children.add (O.Renderer.children renderer)
          (Tab_controller.as_renderable controller)));
  let interactive_spec, toggle_border = interactive_tab renderer context in
  List.iter
    (fun spec -> ignore (Tab_controller.add_tab controller spec))
    [ text_attributes_tab renderer context; basics_tab renderer context;
      borders_tab renderer context; animation_tab renderer context;
      titles_tab renderer context; interactive_spec ];
  ignore (Tab_controller.focus controller);
  (* Drive the current tab's per-frame update. *)
  ignore
    (expect_ok
       (O.Renderer.attach_pre_render renderer (fun delta_seconds ->
            Tab_controller.update controller (delta_seconds *. 1000.0))));
  (* Interactive border toggles apply only on the Interactive tab. *)
  ignore
    (O.Renderer.on_keypress renderer (fun key_event ->
         if
           String.equal (Tab_controller.current_tab_title controller) "Interactive"
           && O.Lib.Key_handler.key_event_kind key_event = O.Lib.Key_handler.Keypress
         then toggle_border (Some (O.Lib.Key_handler.key_raw key_event))));
  (* Demo-wide keys: backtick/quote toggle the diagnostic console; Ctrl+C
     stops the scheduler so the harness drains output and restores the
     terminal. *)
  Opentui_examples_lib.Standalone_keys.setup_common_demo_keys renderer
    ~on_ctrl_c:exit

let () =
  Eio_main.run @@ fun env ->
  let fps =
    match Sys.getenv_opt "OPENTUI_DEMO_FPS" with
    | Some raw -> (
        match int_of_string_opt raw with
        | Some value when value > 0 -> value
        | Some _ | None ->
            invalid_arg (Printf.sprintf "OPENTUI_DEMO_FPS must be a positive integer, got %S" raw))
    | None -> 30
  in
  Opentui_examples_lib.App.run env ~target_frames_per_second:fps
    ~init:(fun ~exit renderer -> run renderer ~exit)
