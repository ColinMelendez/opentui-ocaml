open Windtrap

module Renderer = Opentui_core.Renderer
module Yoga = Opentui_core.Yoga

(* This helper gives the existing low-level rendering tests an owner for a
   temporary independent-node tree. It is test-local; the public Yoga module
   exposes nodes rather than a tree-owner compatibility layer. *)
module Layout = struct
  type direction = Yoga.direction = Inherit | Ltr | Rtl

  type layout = Yoga.layout = {
    left : float;
    top : float;
    right : float;
    bottom : float;
    width : float;
    height : float;
  }

  type t = {
    root : Yoga.Node.t;
    mutable closed : bool;
  }

  module Node = struct
    type t = Yoga.Node.t
    type edge = Yoga.edge = Left | Top | Right | Bottom | Start | End | Horizontal | Vertical | All

    let max_dimension = 3.4028234663852886e38

    let valid_dimension value =
      match classify_float value with
      | FP_nan | FP_infinite -> false
      | FP_zero | FP_subnormal | FP_normal ->
          Float.compare value 0.0 >= 0
          && Float.compare value max_dimension <= 0

    let set_dimensions node ~width ~height =
      if not (valid_dimension width && valid_dimension height) then
        Error
          (Opentui_core.Native.Error.Native Opentui_raw.Error.Invalid_argument)
      else
        match Yoga.Node.set_width_point node width with
        | Error error -> Error error
        | Ok () -> Yoga.Node.set_height_point node height

    let set_padding node ~edge ~value =
      Yoga.Node.set_padding_point node ~edge ~value

    let layout = Yoga.Node.layout
  end

  let create () =
    match Yoga.Node.create () with
    | Error error -> Error error
    | Ok root -> Ok { root; closed = false }

  let root layout =
    if layout.closed then Error Opentui_core.Native.Error.Closed
    else Ok layout.root

  let add_child ~parent =
    match Yoga.Node.child_count parent with
    | Error error -> Error error
    | Ok count ->
        (match Yoga.Node.create () with
        | Error error -> Error error
        | Ok child ->
            (match Yoga.Node.insert_child ~parent ~child ~index:count with
            | Ok () -> Ok child
            | Error error ->
                (match Yoga.Node.free child with
                | Ok () -> Error error
                | Error cleanup_error -> Error cleanup_error)))

  let remove_child ~parent ~child = Yoga.Node.remove_child ~parent ~child
  let move_child ~parent ~child ~index = Yoga.Node.move_child ~parent ~child ~index

  let calculate layout ~width ~height ~direction =
    Yoga.Node.calculate_layout layout.root ~width ~height ~direction

  let close layout =
    if not layout.closed then begin
      layout.closed <- true;
      ignore (Yoga.Node.free_recursive layout.root)
    end
end

module Text_renderable = Opentui_core.Renderables.Text
module Box_renderable = Opentui_core.Renderables.Box

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Opentui_core.Native.Error.message error)

let same_error left right =
  match left, right with
  | Opentui_core.Native.Error.Closed, Opentui_core.Native.Error.Closed -> true
  | Opentui_core.Native.Error.Frame_already_open,
    Opentui_core.Native.Error.Frame_already_open -> true
  | Opentui_core.Native.Error.Frame_not_open, Opentui_core.Native.Error.Frame_not_open ->
      true
  | Opentui_core.Native.Error.Native left, Opentui_core.Native.Error.Native right ->
      (match left, right with
      | Opentui_raw.Error.Invalid_argument,
        Opentui_raw.Error.Invalid_argument -> true
      | Opentui_raw.Error.Output_too_small,
        Opentui_raw.Error.Output_too_small -> true
      | Opentui_raw.Error.Stale_handle, Opentui_raw.Error.Stale_handle -> true
      | _ -> false)
  | _ -> false

let expect_error expected result =
  match result with
  | Ok _ -> fail "expected an error"
  | Error actual -> equal bool true (same_error expected actual)

let () =
  run "opentui-core-renderer"
    [
      test "an imperative frame owns the native next buffer" (fun () ->
          let renderer =
            expect_ok (Renderer.create ~width:2l ~height:1l)
          in
          let frame = expect_ok (Renderer.begin_frame renderer) in
          ignore
            (expect_ok
               (Renderer.Frame.clear frame
                  ~background:Opentui_core.Color.black));
          ignore
            (expect_ok
               (Renderer.Frame.set_cell frame ~x:0l ~y:0l ~character:65l
                  ~foreground:Opentui_core.Color.white
                  ~background:Opentui_core.Color.black ~attributes:0l));
          ignore
            (expect_ok
               (Renderer.Frame.draw_text frame ~text:"B" ~x:1l ~y:0l
                  ~foreground:Opentui_core.Color.white
                  ~background:Opentui_core.Color.black ~attributes:0l));
          let output = Bytes.create 2 in
          let written =
            expect_ok
              (Renderer.Frame.write_resolved_chars frame ~output
                 ~add_line_breaks:false)
          in
          equal int32 2l written;
          equal string "AB" (Bytes.to_string output);
          expect_error
            (Opentui_core.Native.Error.Native Opentui_raw.Error.Output_too_small)
            (Renderer.Frame.write_resolved_chars frame
               ~output:(Bytes.create 1) ~add_line_breaks:false);
          (match expect_ok (Renderer.present frame ~force:true) with
          | Renderer.Rendered -> ()
          | Renderer.Skipped -> fail "expected the memory frame to render"
          | Renderer.Failed -> fail "the native frame failed");
          expect_error Opentui_core.Native.Error.Frame_not_open
            (Renderer.Frame.write_resolved_chars frame ~output
               ~add_line_breaks:false);
          Renderer.close renderer);
      test "frame ownership rejects overlap and reuse" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:1l ~height:1l) in
          let frame = expect_ok (Renderer.begin_frame renderer) in
          expect_error Opentui_core.Native.Error.Frame_already_open
            (Renderer.begin_frame renderer);
          ignore (expect_ok (Renderer.present frame ~force:true));
          expect_error Opentui_core.Native.Error.Frame_not_open
            (Renderer.present frame ~force:true);
          let next_frame = expect_ok (Renderer.begin_frame renderer) in
          ignore (expect_ok (Renderer.present next_frame ~force:true));
          Renderer.close renderer);
      test "run_frame composes drawing and present" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:1l ~height:1l) in
          (match
             Renderer.run_frame renderer ~force:true ~draw:(fun frame ->
                 Renderer.Frame.clear frame
                   ~background:Opentui_core.Color.black)
           with
          | Ok Renderer.Rendered -> ()
          | Ok Renderer.Skipped -> fail "expected the memory frame to render"
          | Ok Renderer.Failed -> fail "the native frame failed"
          | Error error -> fail (Opentui_core.Native.Error.message error));
          Renderer.close renderer);
      test "run_frame abandons a failed draw for reuse" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:1l ~height:1l) in
          expect_error Opentui_core.Native.Error.Frame_not_open
            (Renderer.run_frame renderer ~force:true ~draw:(fun frame ->
                 ignore
                   (expect_ok
                      (Renderer.Frame.set_cell frame ~x:0l ~y:0l
                         ~character:88l ~foreground:Opentui_core.Color.white
                         ~background:Opentui_core.Color.black ~attributes:0l));
                 Error Opentui_core.Native.Error.Frame_not_open));
          let frame = expect_ok (Renderer.begin_frame renderer) in
          let output = Bytes.create 1 in
          equal int32 1l
            (expect_ok
               (Renderer.Frame.write_resolved_chars frame ~output
                  ~add_line_breaks:false));
          equal string " " (Bytes.to_string output);
          ignore (expect_ok (Renderer.present frame ~force:true));
          Renderer.close renderer);
      test "run_frame releases a frame when drawing raises" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:1l ~height:1l) in
          let raised =
            try
              ignore
                (Renderer.run_frame renderer ~force:true ~draw:(fun frame ->
                     ignore frame;
                     raise Exit));
              false
            with
            | Exit -> true
          in
          equal bool true raised;
          let frame = expect_ok (Renderer.begin_frame renderer) in
          ignore (expect_ok (Renderer.present frame ~force:true));
          Renderer.close renderer);
      test "resize is serialized with the imperative frame" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:2l ~height:1l) in
          let frame = expect_ok (Renderer.begin_frame renderer) in
          expect_error Opentui_core.Native.Error.Frame_already_open
            (Renderer.resize renderer ~width:3l ~height:2l);
          ignore (expect_ok (Renderer.present frame ~force:true));
          ignore
            (expect_ok (Renderer.resize renderer ~width:3l ~height:2l));
          expect_error
            (Opentui_core.Native.Error.Native Opentui_raw.Error.Invalid_argument)
            (Renderer.resize renderer ~width:0l ~height:2l);
          Renderer.close renderer);
      test "closed renderer invalidates its frame token" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:1l ~height:1l) in
          let frame = expect_ok (Renderer.begin_frame renderer) in
          Renderer.close renderer;
          expect_error Opentui_core.Native.Error.Closed
            (Renderer.Frame.clear frame ~background:Opentui_core.Color.black);
          expect_error Opentui_core.Native.Error.Closed
            (Renderer.present frame ~force:true));
      test "native creation errors stay structured" (fun () ->
          expect_error
            (Opentui_core.Native.Error.Native Opentui_raw.Error.Invalid_argument)
            (Renderer.create ~width:0l ~height:1l));
      test "native colors keep construction behind the native package" (fun () ->
          expect_error
            (Opentui_core.Native.Error.Native Opentui_raw.Error.Invalid_argument)
            (Opentui_core.Color.rgba ~red:256 ~green:0 ~blue:0
               ~alpha:255));
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
               (Layout.Node.set_padding root ~edge:Layout.Node.Left
                  ~value:1.0));
          ignore
            (expect_ok
               (Layout.Node.set_padding root ~edge:Layout.Node.Top
                  ~value:1.0));
          ignore
            (expect_ok
               (Layout.calculate layout ~width:100.0 ~height:40.0
                  ~direction:Layout.Ltr));
          let root_layout = expect_ok (Layout.Node.layout root) in
          equal (float 0.0001) 100.0 root_layout.Layout.width;
          equal (float 0.0001) 40.0 root_layout.Layout.height;
          let child_layout = expect_ok (Layout.Node.layout child) in
          equal (float 0.0001) 1.0 child_layout.Layout.left;
          equal (float 0.0001) 1.0 child_layout.Layout.top;
          equal (float 0.0001) 10.0 child_layout.Layout.width;
          equal (float 0.0001) 5.0 child_layout.Layout.height;
          Layout.close layout;
          expect_error
            (Opentui_core.Native.Error.Native Opentui_raw.Error.Stale_handle)
            (Layout.Node.layout child);
          expect_error Opentui_core.Native.Error.Closed (Layout.root layout));
      test "layout rejects invalid dimensions before mutating Yoga" (fun () ->
          let layout = expect_ok (Layout.create ()) in
          let root = expect_ok (Layout.root layout) in
          let child = expect_ok (Layout.add_child ~parent:root) in
          ignore
            (expect_ok
               (Layout.Node.set_dimensions child ~width:3.0 ~height:4.0));
          expect_error
            (Opentui_core.Native.Error.Native Opentui_raw.Error.Invalid_argument)
            (Layout.Node.set_dimensions child ~width:10.0
               ~height:Float.max_float);
          expect_error
            (Opentui_core.Native.Error.Native Opentui_raw.Error.Invalid_argument)
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
            (Opentui_core.Native.Error.Native Opentui_raw.Error.Invalid_argument)
            (Layout.Node.set_dimensions root ~width:Float.nan ~height:1.0);
          Layout.close layout);
      test "layout moves a child while retaining its computed identity" (fun () ->
          let layout = expect_ok (Layout.create ()) in
          let root = expect_ok (Layout.root layout) in
          let first = expect_ok (Layout.add_child ~parent:root) in
          let second = expect_ok (Layout.add_child ~parent:root) in
          ignore
            (expect_ok
               (Layout.Node.set_dimensions first ~width:4.0 ~height:1.0));
          ignore
            (expect_ok
               (Layout.Node.set_dimensions second ~width:4.0 ~height:2.0));
          ignore
            (expect_ok
               (Layout.calculate layout ~width:4.0 ~height:10.0
                  ~direction:Layout.Ltr));
          equal (float 0.0001) 0.0
            (expect_ok (Layout.Node.layout first)).Layout.top;
          equal (float 0.0001) 1.0
            (expect_ok (Layout.Node.layout second)).Layout.top;
          expect_error
            (Opentui_core.Native.Error.Native Opentui_raw.Error.Invalid_argument)
            (Layout.move_child ~parent:root ~child:second ~index:2l);
          equal (float 0.0001) 0.0
            (expect_ok (Layout.Node.layout first)).Layout.top;
          equal (float 0.0001) 1.0
            (expect_ok (Layout.Node.layout second)).Layout.top;
          ignore
            (expect_ok
               (Layout.move_child ~parent:root ~child:second ~index:0l));
          ignore
            (expect_ok
               (Layout.calculate layout ~width:4.0 ~height:10.0
                  ~direction:Layout.Ltr));
          equal (float 0.0001) 2.0
            (expect_ok (Layout.Node.layout first)).Layout.top;
          equal (float 0.0001) 0.0
            (expect_ok (Layout.Node.layout second)).Layout.top;
          Layout.close layout;
          expect_error
            (Opentui_core.Native.Error.Native Opentui_raw.Error.Stale_handle)
            (Layout.Node.layout second));
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
                  ~background:Opentui_core.Color.black));
          ignore
            (expect_ok
               (Text_renderable.draw renderable frame
                  ~offset_x:0.0 ~offset_y:0.0
                  ~foreground:Opentui_core.Color.white
                  ~background:Opentui_core.Color.black ~attributes:0l));
          ignore (expect_ok (Renderer.present frame ~force:true));
          expect_error Opentui_core.Native.Error.Frame_not_open
            (Text_renderable.draw renderable frame
               ~offset_x:0.0 ~offset_y:0.0
               ~foreground:Opentui_core.Color.white
               ~background:Opentui_core.Color.black ~attributes:0l);
          let next_frame = expect_ok (Renderer.begin_frame renderer) in
          Layout.close layout;
          expect_error
            (Opentui_core.Native.Error.Native Opentui_raw.Error.Stale_handle)
            (Text_renderable.draw renderable next_frame
               ~offset_x:0.0 ~offset_y:0.0
               ~foreground:Opentui_core.Color.white
               ~background:Opentui_core.Color.black ~attributes:0l);
          Renderer.close renderer);
      test "a box renderable draws its retained border through the frame seam"
        (fun () ->
          let renderer = expect_ok (Renderer.create ~width:4l ~height:2l) in
          let layout = expect_ok (Layout.create ()) in
          let root = expect_ok (Layout.root layout) in
          ignore
            (expect_ok
               (Layout.calculate layout ~width:4.0 ~height:2.0
                  ~direction:Layout.Ltr));
          let renderable =
            Box_renderable.create ~node:root
              ~border:Box_renderable.Single ()
          in
          let frame = expect_ok (Renderer.begin_frame renderer) in
          ignore
            (expect_ok
               (Renderer.Frame.clear frame
                  ~background:Opentui_core.Color.black));
          ignore
            (expect_ok
               (Box_renderable.draw renderable frame
                  ~offset_x:0.0 ~offset_y:0.0));
          let output = Bytes.create 32 in
          let written =
            expect_ok
              (Renderer.Frame.write_resolved_chars frame ~output
                 ~add_line_breaks:false)
          in
          equal string "┌──┐└──┘"
            (Bytes.sub_string output 0 (Int32.to_int written));
          ignore (expect_ok (Renderer.present frame ~force:true));
          Layout.close layout;
          Renderer.close renderer)
    ]
