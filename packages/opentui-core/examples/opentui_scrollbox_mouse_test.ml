(* Port of vendor/opentui/packages/examples/src/scrollbox-mouse-test.ts.

   A focused survival test for scrolling: 50 same-height item rows inside a
   Scroll_box, each reporting mouse-over/out so we can tell whether scrolled
   content keeps correct hit-testing and whether rendering stays coherent
   while the box translates its content. *)

module O = Opentui_core
module S = O.Lib.Styled_text
module Util = Opentui_examples_lib.Util
module Box = O.Renderables.Box
module Text = O.Renderables.Text
module Scroll_box = O.Renderables.Scroll_box

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> invalid_arg (O.Error.message error)

let color = Util.color_of_hex
let with_fg fg_text text = S.create [ S.chunk ~fg:(color fg_text) text ]

let run renderer ~exit ~copy_to_clipboard =
  ignore copy_to_clipboard;
  ignore (expect_ok (O.Renderer.set_background_color renderer ~color:(color "#1a1b26")));
  let context = O.Renderer.context renderer in
  (* Main column container. *)
  let main =
    expect_ok
      (Box.create context ~id:"main-container"
         ~background_color:(color "#1a1b26") ())
  in
  ignore (expect_ok (O.Renderable.set_flex_direction (Box.as_renderable main) O.Yoga.Flex_column));
  ignore (expect_ok (O.Renderable.set_flex_grow (Box.as_renderable main) (Some 1.0)));
  ignore (expect_ok (O.Renderable.set_max_width (Box.as_renderable main) (O.Yoga.Percent 100.0)));
  ignore (expect_ok (O.Renderable.set_max_height (Box.as_renderable main) (O.Yoga.Percent 100.0)));
  ignore (expect_ok (O.Layout_children.add (O.Renderer.children renderer) (Box.as_renderable main)));
  (* Header. *)
  let header =
    expect_ok
      (Box.create context ~id:"header"
         ~background_color:(color "#24283b") ())
  in
  ignore (expect_ok (O.Renderable.set_height (Box.as_renderable header) (O.Yoga.Point 3.0)));
  ignore (expect_ok (O.Renderable.set_width (Box.as_renderable header) (O.Yoga.Percent 100.0)));
  ignore (expect_ok (O.Renderable.set_flex_shrink (Box.as_renderable header) (Some 0.0)));
  ignore
    (expect_ok
       (O.Renderable.set_padding (Box.as_renderable header)
          ~edge:O.Yoga.Left (O.Yoga.Point 1.0)));
  ignore (expect_ok (O.Layout_children.add (Box.children main) (Box.as_renderable header)));
  let title =
    expect_ok
      (Text.create context
         ~content:(with_fg "#7aa2f7" "ScrollBox Mouse Hit Test - scroll and hover items") ())
  in
  ignore (expect_ok (O.Layout_children.add (Box.children header) (Text.as_renderable title)));
  let status =
    expect_ok
      (Text.create context
         ~content:(S.append (with_fg "#565f89" "Hovered: ") (with_fg "#c0caf5" "none"))
         ())
  in
  ignore (expect_ok (O.Layout_children.add (Box.children header) (Text.as_renderable status)));
  let hovered = ref None in
  let update_status () =
    let value = Option.value !hovered ~default:"none" in
    ignore
      (expect_ok
         (Text.set_content status
            (S.append (with_fg "#565f89" "Hovered: ") (with_fg "#9ece6a" value))))
  in
  (* Bordered frame around the scroll area (the OCaml Scroll_box exposes no
     root styling, so the reference's rootOptions border+background live here). *)
  let frame =
    expect_ok
      (Box.create context ~id:"scroll-frame"
         ~background_color:(color "#24283b")
         ~border_style:O.Lib.Border.Single ~border:O.Lib.Border.All_borders
         ~border_color:(color "#7aa2f7") ())
  in
  ignore (expect_ok (O.Renderable.set_flex_grow (Box.as_renderable frame) (Some 1.0)));
  ignore (expect_ok (O.Renderable.set_overflow (Box.as_renderable frame) O.Yoga.Overflow_hidden));
  ignore (expect_ok (O.Layout_children.add (Box.children main) (Box.as_renderable frame)));
  let scroll_box =
    expect_ok
      (Scroll_box.create context ~id:"scroll-box" ~scroll_y:true
         ~scroll_x:false ())
  in
  ignore (expect_ok (O.Renderable.set_flex_grow (Scroll_box.as_renderable scroll_box) (Some 1.0)));
  ignore (expect_ok (O.Layout_children.add (Box.children frame) (Scroll_box.as_renderable scroll_box)));
  let content_surface =
    expect_ok
      (Box.create context ~id:"scroll-content"
         ~background_color:(color "#16161e") ())
  in
  ignore
    (expect_ok
       (O.Renderable.set_width (Box.as_renderable content_surface)
          (O.Yoga.Percent 100.0)));
  ignore
    (expect_ok
       (O.Renderable.set_height (Box.as_renderable content_surface)
          (O.Yoga.Point 100.0)));
  ignore
    (expect_ok
       (O.Renderable.set_flex_shrink (Box.as_renderable content_surface)
          (Some 0.0)));
  ignore (expect_ok (Scroll_box.add scroll_box (Box.as_renderable content_surface)));
  let item_colors = [| color "#292e42"; color "#2f3449" |] in
  let hover_color = color "#3b4261" in
  ignore
    (Array.init 50 (fun i ->
        let background = item_colors.(i mod 2) in
        let item =
          expect_ok
            (Box.create context
               ~id:(Printf.sprintf "item-%d" i) ~background_color:background ())
        in
        ignore (expect_ok (O.Renderable.set_height (Box.as_renderable item) (O.Yoga.Point 2.0)));
        ignore (expect_ok (O.Renderable.set_width (Box.as_renderable item) (O.Yoga.Percent 100.0)));
        ignore
          (expect_ok
             (O.Renderable.set_padding (Box.as_renderable item)
                ~edge:O.Yoga.Left (O.Yoga.Point 1.0)));
        let pressed = ref false in
        let contains_pointer event =
          let renderable = Box.as_renderable item in
          let left = int_of_float (Float.floor (O.Renderable.screen_x renderable)) in
          let top = int_of_float (Float.floor (O.Renderable.screen_y renderable)) in
          let right =
            int_of_float (Float.ceil (O.Renderable.screen_x renderable +. O.Renderable.width renderable))
          in
          let bottom =
            int_of_float (Float.ceil (O.Renderable.screen_y renderable +. O.Renderable.height renderable))
          in
          let x = O.Renderable.mouse_x event in
          let y = O.Renderable.mouse_y event in
          Int.compare x left >= 0 && Int.compare x right < 0
          && Int.compare y top >= 0 && Int.compare y bottom < 0
        in
        ignore
          (expect_ok
             (O.Renderable.set_on_mouse_over (Box.as_renderable item)
                (Some (fun _event ->
                     hovered := Some (Printf.sprintf "item-%d" i);
                     ignore (expect_ok (O.Renderer.set_mouse_pointer renderer O.Renderer.Mouse_pointer));
                     ignore (expect_ok (Box.set_background_color item hover_color));
                     update_status ()))));
        ignore
          (expect_ok
             (O.Renderable.set_on_mouse_move (Box.as_renderable item)
                (Some (fun event ->
                     if !pressed && not (contains_pointer event) then
                       pressed := false))));
        ignore
          (expect_ok
             (O.Renderable.set_on_mouse_out (Box.as_renderable item)
                (Some (fun _event ->
                     pressed := false;
                     if String.equal
                          (Option.value !hovered ~default:"")
                          (Printf.sprintf "item-%d" i)
                     then begin
                       hovered := None;
                       ignore (expect_ok (O.Renderer.set_mouse_pointer renderer O.Renderer.Mouse_default));
                       ignore (expect_ok (Box.set_background_color item background));
                       update_status ()
                     end))));
        ignore
          (expect_ok
             (O.Renderable.set_on_mouse_down (Box.as_renderable item)
                (Some (fun event ->
                     if Int.equal (O.Renderable.mouse_button event) 0 then begin
                       pressed := true;
                       O.Renderable.mouse_capture event
                     end))));
        ignore
          (expect_ok
             (O.Renderable.set_on_mouse_up (Box.as_renderable item)
                (Some (fun event ->
                     if Int.equal (O.Renderable.mouse_button event) 0
                        && !pressed
                     then begin
                       pressed := false;
                       if contains_pointer event then
                         begin
                           ignore
                             (O.Console.log (O.Renderer.console renderer)
                                (Printf.sprintf "Clicked item-%d" i));
                           ignore (O.Renderer.request_render renderer)
                         end
                     end))));
        let label =
          expect_ok
            (Text.create context
               ~content:
                 (S.append (with_fg "#7aa2f7" (Printf.sprintf "[%02d]" i))
                    (S.append (S.of_string " ")
                       (with_fg "#c0caf5"
                          (Printf.sprintf "Item %d - Hover over me" i))))
               ())
        in
        ignore (expect_ok (O.Layout_children.add (Box.children item) (Text.as_renderable label)));
        ignore (expect_ok (O.Layout_children.add (Box.children content_surface) (Box.as_renderable item)));
        item))
  ;
  (* Give the Scroll_box focus so keyboard scrolling participates; arrow keys
     also move through the box, complementing mouse-wheel scrolling. *)
  ignore (expect_ok (O.Renderable.focus (Scroll_box.as_renderable scroll_box)));
  (* Common demo keys: Ctrl+C exits, backtick/quote toggles the console. *)
  Opentui_examples_lib.Standalone_keys.setup_common_demo_keys renderer
    ~on_ctrl_c:exit

let () =
  Eio_main.run @@ fun env ->
  Opentui_examples_lib.App.run env
    ~init:(fun ~exit ~copy_to_clipboard renderer ->
      run renderer ~exit ~copy_to_clipboard)
