open Windtrap

module Renderer = Opentui_native.Renderer

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
    ]
