open Windtrap

module Core = Opentui_core
module Renderer = Core.Renderer
module Text_buffer = Core.Text_buffer
module Text_buffer_view = Core.Text_buffer_view
module Text_buffer_renderable = Core.Renderables.Text_buffer_renderable

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Core.Error.message error)

let expect_error expected result =
  match result with
  | Ok _ -> fail "expected an error"
  | Error actual ->
      equal bool true
        (match expected, actual with
        | Core.Error.Closed, Core.Error.Closed -> true
        | Core.Error.Destroyed, Core.Error.Destroyed -> true
        | _ -> false)

let expect_native_invalid_argument result =
  match result with
  | Error
      (Core.Error.Native
        (Core.Native.Error.Native Opentui_raw.Error.Invalid_argument)) ->
      ()
  | Ok _ -> fail "expected a native invalid-argument error"
  | Error error -> fail (Core.Error.message error)

let expect_float label expected actual =
  if Float.abs (expected -. actual) > 0.0001 then
    fail
      (Printf.sprintf "%s: expected %.3f, got %.3f" label expected actual)

let () =
  run "opentui-core-text-buffer"
    [
      test "typed storage and views preserve native measurement" (fun () ->
          let buffer = expect_ok (Text_buffer.create Text_buffer.Unicode) in
          let view = expect_ok (Text_buffer_view.create buffer) in
          ignore (expect_ok (Text_buffer.set_text buffer "ABCDEFGHIJ"));
          ignore
            (expect_ok
               (Text_buffer_view.set_wrap_mode view Text_buffer_view.Char));
          Gc.compact ();
          let measure =
            expect_ok
              (Text_buffer_view.measure_for_dimensions view ~width:5l ~height:10l)
          in
          equal int32 2l measure.line_count;
          equal int32 5l measure.width_cols_max;
          ignore (expect_ok (Text_buffer_view.close view));
          ignore (expect_ok (Text_buffer.close buffer));
          expect_error Core.Error.Closed
            (Text_buffer.append buffer "closed"));
      test "wrap modes preserve constrained and intrinsic measurement" (fun () ->
          let buffer = expect_ok (Text_buffer.create Text_buffer.Unicode) in
          let view = expect_ok (Text_buffer_view.create buffer) in
          ignore (expect_ok (Text_buffer.set_text buffer "ABCDEFGHIJ"));
          ignore
            (expect_ok
               (Text_buffer_view.set_wrap_mode view Text_buffer_view.Char));
          let constrained =
            expect_ok
              (Text_buffer_view.measure_for_dimensions view ~width:5l
                 ~height:10l)
          in
          equal int32 2l constrained.line_count;
          equal int32 5l constrained.width_cols_max;
          let intrinsic =
            expect_ok
              (Text_buffer_view.measure_for_dimensions view ~width:0l
                 ~height:10l)
          in
          equal int32 1l intrinsic.line_count;
          equal int32 10l intrinsic.width_cols_max;
          ignore
            (expect_ok
               (Text_buffer_view.set_wrap_mode view Text_buffer_view.No_wrap));
          let no_wrap =
            expect_ok
              (Text_buffer_view.measure_for_dimensions view ~width:5l
                 ~height:10l)
          in
          equal int32 1l no_wrap.line_count;
          equal int32 10l no_wrap.width_cols_max;
          ignore (expect_ok (Text_buffer_view.close view));
          ignore (expect_ok (Text_buffer.close buffer)));
      test "text-buffer renderable attaches a native measure target" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:5l ~height:10l) in
          let text =
            expect_ok
              (Text_buffer_renderable.create (Renderer.context renderer)
                 ~wrap_mode:Text_buffer_view.Char ())
          in
          ignore (expect_ok (Text_buffer_renderable.set_text text "ABCDEFGHIJ"));
          ignore
            (expect_ok
               (Core.Layout_children.add (Renderer.children renderer)
                  (Text_buffer_renderable.as_renderable text)));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          let first_layout =
            expect_ok
              (Core.Renderable.layout
                 (Text_buffer_renderable.as_renderable text))
          in
          expect_float "first width" 5.0 first_layout.width;
          expect_float "first height" 2.0 first_layout.height;
          ignore (expect_ok (Text_buffer_renderable.set_text text "ABCDE"));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          let second_layout =
            expect_ok
              (Core.Renderable.layout
                 (Text_buffer_renderable.as_renderable text))
          in
          expect_float "second height" 1.0 second_layout.height;
          Text_buffer_renderable.destroy text;
          expect_error Core.Error.Destroyed
            (Text_buffer_renderable.set_text text "after-destroy");
          Text_buffer_renderable.destroy text;
          Renderer.destroy renderer);
      test "text-buffer renderable draws its view into the renderer buffer" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:6l ~height:2l) in
          let text =
            expect_ok
              (Text_buffer_renderable.create (Renderer.context renderer)
                 ~wrap_mode:Text_buffer_view.No_wrap ())
          in
          ignore (expect_ok (Text_buffer_renderable.set_text text "AB"));
          ignore
            (expect_ok
               (Core.Layout_children.add (Renderer.children renderer)
                  (Text_buffer_renderable.as_renderable text)));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          let output = Bytes.create 12 in
          let written =
            expect_ok
              (Core.Buffer.write_resolved_chars
                 (expect_ok (Renderer.current_buffer renderer)) ~output
                 ~add_line_breaks:false)
          in
          equal int32 12l written;
          equal string "AB          " (Bytes.to_string output);
          Renderer.destroy renderer);
      test "text-buffer renderable forwards signed screen coordinates" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:6l ~height:2l) in
          let text =
            expect_ok
              (Text_buffer_renderable.create (Renderer.context renderer)
                 ~wrap_mode:Text_buffer_view.No_wrap ())
          in
          let renderable = Text_buffer_renderable.as_renderable text in
          ignore (expect_ok (Text_buffer_renderable.set_text text "AB"));
          ignore
            (expect_ok
               (Core.Layout_children.add (Renderer.children renderer) renderable));
          ignore (expect_ok (Core.Renderable.set_translate_x renderable (-1.0)));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          let output = Bytes.create 12 in
          ignore
            (expect_ok
               (Core.Buffer.write_resolved_chars
                  (expect_ok (Renderer.current_buffer renderer)) ~output
                  ~add_line_breaks:false));
          equal string "B           " (Bytes.to_string output);
          Renderer.destroy renderer);
      test "text mutations invalidate Yoga measurement" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:5l ~height:10l) in
          let text =
            expect_ok
              (Text_buffer_renderable.create (Renderer.context renderer)
                 ~wrap_mode:Text_buffer_view.Char ())
          in
          ignore (expect_ok (Text_buffer_renderable.set_text text "ABCDE"));
          ignore
            (expect_ok
               (Core.Layout_children.add (Renderer.children renderer)
                  (Text_buffer_renderable.as_renderable text)));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          let first_layout =
            expect_ok
              (Core.Renderable.layout
                 (Text_buffer_renderable.as_renderable text))
          in
          expect_float "initial height" 1.0 first_layout.height;
          ignore (expect_ok (Text_buffer_renderable.append text "F"));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          let appended_layout =
            expect_ok
              (Core.Renderable.layout
                 (Text_buffer_renderable.as_renderable text))
          in
          expect_float "appended height" 2.0 appended_layout.height;
          ignore (expect_ok (Text_buffer_renderable.clear text));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          let cleared_layout =
            expect_ok
              (Core.Renderable.layout
                 (Text_buffer_renderable.as_renderable text))
          in
          expect_float "cleared height" 1.0 cleared_layout.height;
          Renderer.destroy renderer);
      test "resize invalidates the text measure constraints" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:10l ~height:10l) in
          let text =
            expect_ok
              (Text_buffer_renderable.create (Renderer.context renderer)
                 ~wrap_mode:Text_buffer_view.Char ())
          in
          ignore
            (expect_ok (Text_buffer_renderable.set_text text "ABCDEFGHIJ"));
          ignore
            (expect_ok
               (Core.Layout_children.add (Renderer.children renderer)
                  (Text_buffer_renderable.as_renderable text)));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          let before_resize =
            expect_ok
              (Core.Renderable.layout
                 (Text_buffer_renderable.as_renderable text))
          in
          expect_float "pre-resize height" 1.0 before_resize.height;
          ignore (expect_ok (Renderer.resize renderer ~width:5l ~height:10l));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          let after_resize =
            expect_ok
              (Core.Renderable.layout
                 (Text_buffer_renderable.as_renderable text))
          in
          expect_float "post-resize height" 2.0 after_resize.height;
          Renderer.destroy renderer);
      test "detached text renderables retain their measure owner" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:5l ~height:10l) in
          let text =
            expect_ok
              (Text_buffer_renderable.create (Renderer.context renderer)
                 ~wrap_mode:Text_buffer_view.Char ())
          in
          ignore (expect_ok (Text_buffer_renderable.set_text text "ABCDEFGHIJ"));
          let child = Text_buffer_renderable.as_renderable text in
          ignore
            (expect_ok
               (Core.Layout_children.add (Renderer.children renderer) child));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          ignore (expect_ok (Core.Layout_children.remove (Renderer.children renderer) child));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          ignore
            (expect_ok
               (Core.Layout_children.add (Renderer.children renderer) child));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          let layout = expect_ok (Core.Renderable.layout child) in
          expect_float "reattached height" 2.0 layout.height;
          Renderer.destroy renderer);
      test "native close guards preserve ownership order" (fun () ->
          let buffer = expect_ok (Text_buffer.create Text_buffer.Unicode) in
          let view = expect_ok (Text_buffer_view.create buffer) in
          expect_native_invalid_argument (Text_buffer.close buffer);
          ignore (expect_ok (Text_buffer_view.close view));
          ignore (expect_ok (Text_buffer.close buffer)))
    ]
