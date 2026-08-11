module Core = Opentui_core.Scene
module Core_node = Core.Node

let fail message =
  prerr_endline message;
  Stdlib.exit 1

let expect_ok result =
  match result with
  | Ok value -> value
  | Error _ -> fail "retained benchmark operation failed"

let expect_unit result =
  match result with
  | Ok () -> ()
  | Error _ -> fail "retained benchmark operation failed"

let width = 80
let height = 24

let row_text row =
  String.init width (fun column ->
      Char.chr (Char.code 'A' + ((row + column) mod 26)))

let flush_rendered scene output expected_bytes message =
  match Core.flush scene ~force:false ~output with
  | Ok { Core.status = Core.Rendered; bytes_written } ->
      if not (Int32.equal bytes_written expected_bytes) then fail message
  | Ok { status = Core.Skipped; _ } -> fail message
  | Ok { status = Core.Failed; _ } -> fail message
  | Error _ -> fail message

module Text = struct
  type t = {
    scene : Core.t;
    nodes : Core_node.t array;
    texts : string array;
    output : bytes;
    expected_bytes : int32;
    mutable next_frame : int;
  }

  let create () =
    let scene =
      expect_ok
        (Core.create ~width:(Int32.of_int width) ~height:(Int32.of_int height))
    in
    let root = expect_ok (Core.root scene) in
    let texts = Array.init height row_text in
    let nodes =
      Array.init height (fun row ->
          expect_ok
            (Core_node.create_text ~parent:root ~width:(Float.of_int width)
               ~height:1.0 ~text:(Array.get texts row) ()))
    in
    let output = Bytes.create (width * height) in
    {
      scene;
      nodes;
      texts;
      output;
      expected_bytes = Int32.of_int (Bytes.length output);
      next_frame = 0;
    }

  let run fixture =
    let frame_number = fixture.next_frame in
    fixture.next_frame <- frame_number + 1;
    let row = frame_number mod height in
    expect_unit
      (Core_node.set_text (Array.get fixture.nodes row)
         ~text:(Array.get fixture.texts ((row + frame_number) mod height)));
    flush_rendered fixture.scene fixture.output fixture.expected_bytes
      "retained text benchmark produced an unexpected result"

  let close fixture = Core.close fixture.scene
end

module Frame = Text

module Layout = struct
  type t = {
    scene : Core.t;
    nodes : Core_node.t array;
    output : bytes;
    expected_bytes : int32;
    mutable next_iteration : int;
  }

  let create () =
    let scene =
      expect_ok
        (Core.create ~width:(Int32.of_int width) ~height:(Int32.of_int height))
    in
    let root = expect_ok (Core.root scene) in
    let nodes =
      Array.init height (fun row ->
          expect_ok
            (Core_node.create_text ~parent:root ~width:(Float.of_int width)
               ~height:1.0 ~text:(row_text row) ()))
    in
    let output = Bytes.create (width * height) in
    flush_rendered scene output (Int32.of_int (Bytes.length output))
      "retained layout benchmark setup failed";
    {
      scene;
      nodes;
      output;
      expected_bytes = Int32.of_int (Bytes.length output);
      next_iteration = 0;
    }

  let run fixture =
    let iteration = fixture.next_iteration in
    fixture.next_iteration <- iteration + 1;
    let row = iteration mod height in
    let node_width =
      if Int.equal (iteration mod 2) 0 then width else width / 2
    in
    expect_unit
      (Core_node.set_dimensions (Array.get fixture.nodes row)
         ~width:(Float.of_int node_width) ~height:1.0);
    flush_rendered fixture.scene fixture.output fixture.expected_bytes
      "retained layout benchmark produced an unexpected result"

  let close fixture = Core.close fixture.scene
end

module Reorder = struct
  type t = {
    scene : Core.t;
    order : Core_node.t array;
    output : bytes;
    expected_bytes : int32;
  }

  let create () =
    let scene =
      expect_ok
        (Core.create ~width:(Int32.of_int width) ~height:(Int32.of_int height))
    in
    let root = expect_ok (Core.root scene) in
    let nodes =
      Array.init height (fun row ->
          expect_ok
            (Core_node.create_text ~parent:root ~width:(Float.of_int width)
               ~height:1.0 ~text:(row_text row) ()))
    in
    let output = Bytes.create (width * height) in
    flush_rendered scene output (Int32.of_int (Bytes.length output))
      "retained reorder benchmark setup failed";
    {
      scene;
      order = nodes;
      output;
      expected_bytes = Int32.of_int (Bytes.length output);
    }

  let run fixture =
    let target = Array.get fixture.order 0 in
    expect_unit (Core_node.move_to_index target ~index:1);
    Array.set fixture.order 0 (Array.get fixture.order 1);
    Array.set fixture.order 1 target;
    flush_rendered fixture.scene fixture.output fixture.expected_bytes
      "retained reorder benchmark produced an unexpected result"

  let close fixture = Core.close fixture.scene
end

module Pointer = struct
  type t = {
    scene : Core.t;
    event : Core.pointer_event;
  }

  let create () =
    let scene =
      expect_ok
        (Core.create ~width:(Int32.of_int width) ~height:(Int32.of_int height))
    in
    let root = expect_ok (Core.root scene) in
    let node =
      expect_ok
        (Core_node.create_text ~parent:root ~width:(Float.of_int width)
           ~height:1.0 ~text:(row_text 0) ())
    in
    let handler node event =
      if Core_node.is_destroyed node then Core.Stop
      else if Int.equal event.Core.button 0 then Core.Continue
      else Core.Stop
    in
    expect_unit (Core_node.set_pointer_handler node handler);
    let output = Bytes.create (width * height) in
    flush_rendered scene output (Int32.of_int (Bytes.length output))
      "retained pointer benchmark setup failed";
    { scene; event = { Core.kind = Core.Move; button = 0; x = 0; y = 0 } }

  let run fixture =
    match expect_ok (Core.dispatch_pointer fixture.scene fixture.event) with
    | Core.Handled _ -> ()
    | Core.Unhandled -> fail "retained pointer benchmark did not hit a node"

  let close fixture = Core.close fixture.scene
end

module Teardown = struct
  type t = {
    scene : Core.t;
    root : Core_node.t;
    texts : string array;
    output : bytes;
    expected_bytes : int32;
    mutable next_iteration : int;
  }

  let create () =
    let scene =
      expect_ok
        (Core.create ~width:(Int32.of_int width) ~height:(Int32.of_int height))
    in
    let root = expect_ok (Core.root scene) in
    let texts = Array.init height row_text in
    let output = Bytes.create (width * height) in
    let expected_bytes = Int32.of_int (Bytes.length output) in
    flush_rendered scene output expected_bytes
      "retained teardown benchmark setup failed";
    { scene; root; texts; output; expected_bytes; next_iteration = 0 }

  let run fixture =
    let iteration = fixture.next_iteration in
    fixture.next_iteration <- iteration + 1;
    let child =
      expect_ok
        (Core_node.create_text ~parent:fixture.root ~width:(Float.of_int width)
           ~height:1.0 ~text:(Array.get fixture.texts (iteration mod height)) ())
    in
    flush_rendered fixture.scene fixture.output fixture.expected_bytes
      "retained teardown benchmark create failed";
    expect_unit (Core_node.destroy child);
    flush_rendered fixture.scene fixture.output fixture.expected_bytes
      "retained teardown benchmark destroy failed"

  let close fixture = Core.close fixture.scene
end
