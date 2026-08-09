open Windtrap

module Renderer = Opentui_native.Renderer
module Layout = Opentui_native.Layout
module Text_renderable = Opentui_native.Text_renderable

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Opentui_native.Error.message error)

let same_error left right =
  match left, right with
  | Opentui_native.Error.Closed, Opentui_native.Error.Closed -> true
  | Opentui_native.Error.Frame_already_open,
    Opentui_native.Error.Frame_already_open -> true
  | Opentui_native.Error.Frame_not_open, Opentui_native.Error.Frame_not_open ->
      true
  | Opentui_native.Error.Native left, Opentui_native.Error.Native right ->
      (match left, right with
      | Opentui_raw.Error.Invalid_argument,
        Opentui_raw.Error.Invalid_argument -> true
      | _ -> false)
  | _ -> false

let expect_error expected result =
  match result with
  | Ok _ -> fail "expected an error"
  | Error actual -> equal bool true (same_error expected actual)

let () =
  run "opentui-native"
    [
      test "an imperative frame owns the native next buffer" (fun () ->
          let renderer =
            expect_ok (Renderer.create ~width:2l ~height:1l)
          in
          let frame = expect_ok (Renderer.begin_frame renderer) in
          ignore
            (expect_ok
               (Renderer.Frame.clear frame
                  ~background:Opentui_raw.Color.black));
          ignore
            (expect_ok
               (Renderer.Frame.set_cell frame ~x:0l ~y:0l ~character:65l
                  ~foreground:Opentui_raw.Color.white
                  ~background:Opentui_raw.Color.black ~attributes:0l));
          ignore
            (expect_ok
               (Renderer.Frame.draw_text frame ~text:"B" ~x:1l ~y:0l
                  ~foreground:Opentui_raw.Color.white
                  ~background:Opentui_raw.Color.black ~attributes:0l));
          (match expect_ok (Renderer.present frame ~force:true) with
          | Renderer.Rendered -> ()
          | Renderer.Skipped -> fail "expected the memory frame to render"
          | Renderer.Failed -> fail "the native frame failed");
          Renderer.close renderer);
      test "frame ownership rejects overlap and reuse" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:1l ~height:1l) in
          let frame = expect_ok (Renderer.begin_frame renderer) in
          expect_error Opentui_native.Error.Frame_already_open
            (Renderer.begin_frame renderer);
          ignore (expect_ok (Renderer.present frame ~force:true));
          expect_error Opentui_native.Error.Frame_not_open
            (Renderer.present frame ~force:true);
          let next_frame = expect_ok (Renderer.begin_frame renderer) in
          ignore (expect_ok (Renderer.present next_frame ~force:true));
          Renderer.close renderer);
      test "resize is serialized with the imperative frame" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:2l ~height:1l) in
          let frame = expect_ok (Renderer.begin_frame renderer) in
          expect_error Opentui_native.Error.Frame_already_open
            (Renderer.resize renderer ~width:3l ~height:2l);
          ignore (expect_ok (Renderer.present frame ~force:true));
          ignore
            (expect_ok (Renderer.resize renderer ~width:3l ~height:2l));
          expect_error
            (Opentui_native.Error.Native Opentui_raw.Error.Invalid_argument)
            (Renderer.resize renderer ~width:0l ~height:2l);
          Renderer.close renderer);
      test "closed renderer invalidates its frame token" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:1l ~height:1l) in
          let frame = expect_ok (Renderer.begin_frame renderer) in
          Renderer.close renderer;
          expect_error Opentui_native.Error.Closed
            (Renderer.Frame.clear frame ~background:Opentui_raw.Color.black);
          expect_error Opentui_native.Error.Closed
            (Renderer.present frame ~force:true));
      test "native creation errors stay structured" (fun () ->
          expect_error
            (Opentui_native.Error.Native Opentui_raw.Error.Invalid_argument)
            (Renderer.create ~width:0l ~height:1l));
      test "an owner-scoped layout composes raw Yoga nodes" (fun () ->
          let layout =
            expect_ok (Layout.create ())
          in
          let root = expect_ok (Layout.root layout) in
          let child = expect_ok (Layout.add_child ~parent:root) in
          ignore
            (expect_ok
               (Layout.Node.set_dimensions child ~width:10.0 ~height:5.0));
          ignore
            (expect_ok
               (Layout.calculate layout ~width:100.0 ~height:40.0
                  ~direction:Layout.Ltr));
          let root_layout = expect_ok (Layout.Node.layout root) in
          equal (float 0.0001) 100.0 root_layout.Layout.width;
          equal (float 0.0001) 40.0 root_layout.Layout.height;
          let child_layout = expect_ok (Layout.Node.layout child) in
          equal (float 0.0001) 10.0 child_layout.Layout.width;
          equal (float 0.0001) 5.0 child_layout.Layout.height;
          Layout.close layout;
          expect_error Opentui_native.Error.Closed
            (Layout.Node.layout child);
          expect_error Opentui_native.Error.Closed (Layout.root layout));
      test "layout rejects invalid dimensions before mutating Yoga" (fun () ->
          let layout = expect_ok (Layout.create ()) in
          let root = expect_ok (Layout.root layout) in
          let child = expect_ok (Layout.add_child ~parent:root) in
          ignore
            (expect_ok
               (Layout.Node.set_dimensions child ~width:3.0 ~height:4.0));
          expect_error
            (Opentui_native.Error.Native Opentui_raw.Error.Invalid_argument)
            (Layout.Node.set_dimensions child ~width:10.0
               ~height:Float.max_float);
          expect_error
            (Opentui_native.Error.Native Opentui_raw.Error.Invalid_argument)
            (Layout.calculate layout ~width:(-1.0) ~height:1.0
               ~direction:Layout.Inherit);
          ignore
            (expect_ok
               (Layout.calculate layout ~width:100.0 ~height:40.0
                  ~direction:Layout.Inherit));
          let child_layout = expect_ok (Layout.Node.layout child) in
          equal (float 0.0001) 3.0 child_layout.Layout.width;
          equal (float 0.0001) 4.0 child_layout.Layout.height;
          expect_error
            (Opentui_native.Error.Native Opentui_raw.Error.Invalid_argument)
            (Layout.Node.set_dimensions root ~width:Float.nan ~height:1.0);
          Layout.close layout);
      test "a text renderable draws through the layout and frame seams" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:4l ~height:1l) in
          let layout = expect_ok (Layout.create ()) in
          let root = expect_ok (Layout.root layout) in
          let node = expect_ok (Layout.add_child ~parent:root) in
          ignore
            (expect_ok
               (Layout.Node.set_dimensions node ~width:2.0 ~height:1.0));
          ignore
            (expect_ok
               (Layout.calculate layout ~width:4.0 ~height:1.0
                  ~direction:Layout.Ltr));
          let renderable = Text_renderable.create ~node ~text:"A" in
          equal string "A" (Text_renderable.text renderable);
          Text_renderable.set_text renderable ~text:"B";
          equal string "B" (Text_renderable.text renderable);
          let frame = expect_ok (Renderer.begin_frame renderer) in
          ignore
            (expect_ok
               (Renderer.Frame.clear frame
                  ~background:Opentui_raw.Color.black));
          ignore
            (expect_ok
               (Text_renderable.draw renderable frame
                  ~foreground:Opentui_raw.Color.white
                  ~background:Opentui_raw.Color.black ~attributes:0l));
          ignore (expect_ok (Renderer.present frame ~force:true));
          expect_error Opentui_native.Error.Frame_not_open
            (Text_renderable.draw renderable frame
               ~foreground:Opentui_raw.Color.white
               ~background:Opentui_raw.Color.black ~attributes:0l);
          let next_frame = expect_ok (Renderer.begin_frame renderer) in
          Layout.close layout;
          expect_error Opentui_native.Error.Closed
            (Text_renderable.draw renderable next_frame
               ~foreground:Opentui_raw.Color.white
               ~background:Opentui_raw.Color.black ~attributes:0l);
          Renderer.close renderer)
    ]
